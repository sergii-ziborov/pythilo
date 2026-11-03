import CoreML
import CryptoKit
import Foundation

/// Answers Python's `pythilo.coreml`: loads Core ML models and runs them on the
/// compute units Python names, timing each prediction. It runs on the calling
/// Python thread, with the GIL released; Core ML predictions are safe there.
///
/// A request and a response are a JSON line followed by raw tensor bytes.
final class CoreMLBridge: @unchecked Sendable {
    static let shared = CoreMLBridge()

    private let lock = NSLock()
    private var models: [String: MLModel] = [:]

    /// The C host's call handler.
    static let handler: PyHostCallHandler = { request, length, response, responseLength in
        let data = request.map { Data(bytes: $0, count: length) } ?? Data()
        let (status, bytes): (Int32, Data)
        do {
            (status, bytes) = (0, try CoreMLBridge.shared.handle(data))
        } catch {
            (status, bytes) = (1, Data(error.localizedDescription.utf8) + Data([0]))
        }
        let buffer = malloc(max(bytes.count, 1))!.assumingMemoryBound(to: CChar.self)
        bytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress { memcpy(buffer, base, bytes.count) }
        }
        response?.pointee = buffer
        responseLength?.pointee = bytes.count
        return status
    }

    func handle(_ request: Data) throws -> Data {
        let split = request.firstIndex(of: 0x0A) ?? request.endIndex
        guard let header = try JSONSerialization.jsonObject(with: request[..<split]) as? [String: Any] else { throw CoreMLFailure("Not a request.") }
        let blob = split < request.endIndex ? request[request.index(after: split)...] : Data()[...]
        switch header["op"] as? String {
        case "devices": return Self.reply(devices())
        case "load": return Self.reply(try load(header))
        case "predict": return try predict(header, blob)
        case "unload":
            lock.withLock { models[header["model"] as? String ?? ""] = nil }
            return Self.reply([:])
        default: throw CoreMLFailure("Unknown request.")
        }
    }

    private func devices() -> [String: Any] {
        var names: [String] = []
        var neuralEngine = false
        for device in MLComputeDevice.allComputeDevices {
            switch device {
            case .cpu: names.append("CPU")
            case .gpu: names.append("GPU")
            case let .neuralEngine(engine):
                neuralEngine = true
                names.append("Neural Engine, \(engine.totalCoreCount) cores")
            @unknown default: names.append("other")
            }
        }
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return ["devices": names, "neuralEngine": neuralEngine, "simulator": simulator, "system": "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
    }

    private static func units(_ name: String) throws -> MLComputeUnits {
        switch name {
        case "all": .all
        case "cpu": .cpuOnly
        case "gpu": .cpuAndGPU
        case "ane": .cpuAndNeuralEngine
        default: throw CoreMLFailure("compute is one of all, cpu, gpu, ane.")
        }
    }

    private func load(_ header: [String: Any]) throws -> [String: Any] {
        guard let path = header["path"] as? String else { throw CoreMLFailure("Name a model.") }
        let source: URL
        if path == "sample:tiny-conv" {
            guard let url = Bundle.main.url(forResource: "TinyConv", withExtension: "mlmodel", subdirectory: "Models") else { throw CoreMLFailure("The sample model is missing from this build.") }
            source = url
        } else {
            source = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: source.path) else { throw CoreMLFailure("No model at \(path).") }
        }
        let started = DispatchTime.now()
        let compiled = try compiledModel(source)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = try Self.units(header["compute"] as? String ?? "all")
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        let id = UUID().uuidString
        lock.withLock { models[id] = model }
        return [
            "id": id,
            "milliseconds": Self.milliseconds(since: started),
            "inputs": model.modelDescription.inputDescriptionsByName.values.sorted { $0.name < $1.name }.map(Self.describe),
            "outputs": model.modelDescription.outputDescriptionsByName.values.sorted { $0.name < $1.name }.map(Self.describe),
        ]
    }

    /// .mlmodel and .mlpackage are compiled once and kept, keyed by the file's
    /// path, size and date; an .mlmodelc is used as it is.
    private func compiledModel(_ source: URL) throws -> URL {
        if source.pathExtension == "mlmodelc" { return source }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let stamp = "\(source.path)|\(attributes[.size] ?? 0)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        let key = SHA256.hash(data: Data(stamp.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "coreml")
        let target = cache.appending(path: "\(key).mlmodelc")
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<URL, Error> = .failure(CoreMLFailure("Compiling did not finish."))
        Task.detached {
            do { outcome = .success(try await MLModel.compileModel(at: source)) } catch { outcome = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        let temporary = try outcome.get()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }

    private func predict(_ header: [String: Any], _ blob: Data.SubSequence) throws -> Data {
        guard let id = header["model"] as? String, let model = lock.withLock({ models[id] }) else { throw CoreMLFailure("That model is not loaded.") }
        var features: [String: MLFeatureValue] = [:]
        for input in header["inputs"] as? [[String: Any]] ?? [] {
            guard let name = input["name"] as? String, let shape = input["shape"] as? [Int],
                  let offset = input["offset"] as? Int, let length = input["length"] as? Int,
                  let type = Self.dataType(input["dtype"] as? String ?? "") else { throw CoreMLFailure("An input is not a float32, float16, float64 or int32 array.") }
            let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: type)
            guard length == array.count * Self.size(of: type), offset + length <= blob.count else { throw CoreMLFailure("\(name): \(length) bytes do not fill shape \(shape).") }
            let start = blob.index(blob.startIndex, offsetBy: offset)
            blob[start ..< blob.index(start, offsetBy: length)].withUnsafeBytes { raw in
                if let base = raw.baseAddress { memcpy(array.dataPointer, base, length) }
            }
            features[name] = MLFeatureValue(multiArray: array)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: features)
        let started = DispatchTime.now()
        let result = try model.prediction(from: provider)
        let milliseconds = Self.milliseconds(since: started)
        var outputs: [[String: Any]] = []
        var scalars: [String: Any] = [:]
        var bytes = Data()
        for name in result.featureNames.sorted() {
            guard let value = result.featureValue(for: name) else { continue }
            if let array = value.multiArrayValue {
                let data = Self.contiguous(array)
                outputs.append(["name": name, "dtype": Self.name(of: array.dataType), "shape": array.shape.map(\.intValue), "offset": bytes.count, "length": data.count])
                bytes += data
            } else if value.type == .double {
                scalars[name] = value.doubleValue
            } else if value.type == .int64 {
                scalars[name] = value.int64Value
            } else if value.type == .string {
                scalars[name] = value.stringValue
            } else if value.type == .dictionary {
                scalars[name] = Dictionary(uniqueKeysWithValues: value.dictionaryValue.map { ("\($0.key)", $0.value.doubleValue) })
            }
        }
        return Self.reply(["milliseconds": milliseconds, "outputs": outputs, "scalars": scalars], bytes)
    }

    private static func contiguous(_ array: MLMultiArray) -> Data {
        let size = Self.size(of: array.dataType)
        var expected = 1
        var contiguous = true
        for (dimension, stride) in zip(array.shape.reversed(), array.strides.reversed()) {
            if stride.intValue != expected { contiguous = false }
            expected *= dimension.intValue
        }
        if contiguous { return Data(bytes: array.dataPointer, count: array.count * size) }
        // A strided output is copied value by value, as float32.
        var values = [Float](repeating: 0, count: array.count)
        for index in 0 ..< array.count { values[index] = array[index].floatValue }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func describe(_ feature: MLFeatureDescription) -> [String: Any] {
        var info: [String: Any] = ["name": feature.name]
        if let constraint = feature.multiArrayConstraint {
            info["shape"] = constraint.shape.map(\.intValue)
            info["dtype"] = name(of: constraint.dataType)
        } else {
            info["type"] = "\(feature.type.rawValue)"
        }
        return info
    }

    private static func dataType(_ name: String) -> MLMultiArrayDataType? {
        switch name {
        case "float32": .float32
        case "float16": .float16
        case "float64": .double
        case "int32": .int32
        default: nil
        }
    }

    private static func name(of type: MLMultiArrayDataType) -> String {
        switch type {
        case .float16: "float16"
        case .double: "float64"
        case .int32: "int32"
        default: "float32"
        }
    }

    private static func size(of type: MLMultiArrayDataType) -> Int {
        switch type {
        case .float16: 2
        case .double: 8
        default: 4
        }
    }

    private static func milliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private static func reply(_ header: [String: Any], _ bytes: Data = Data()) -> Data {
        ((try? JSONSerialization.data(withJSONObject: header)) ?? Data("{}".utf8)) + Data([0x0A]) + bytes
    }
}

struct CoreMLFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
