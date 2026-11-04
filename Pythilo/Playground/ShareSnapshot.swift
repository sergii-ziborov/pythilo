import Compression
import Foundation

/// A whole small project carried in a link's fragment, the same format the
/// website's Playground writes (site/PLAYGROUND-LINKS.md):
///
///     https://pythilo.com/playground/#code=<payload>
///     pythilo://playground/#code=<payload>
///
/// payload = base64url without padding of raw DEFLATE (RFC 1951) of UTF-8 JSON
/// {"v":1,"name":"demo","main":"main.py","files":{"main.py":"print(1)\n"}}.
/// No server holds the code: whoever has the link has the files.
struct ShareSnapshot: Equatable {
    static let version = 1
    static let payloadLimit = 100_000
    static let inflatedLimit = 1024 * 1024
    static let webOrigin = "https://pythilo.com"

    var name: String
    var main: String
    var files: [String: String]

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Reading a link

    /// The project in a link, nil when the link is not a share link at all.
    static func from(url: URL) throws -> ShareSnapshot? {
        let scheme = url.scheme?.lowercased()
        let isApp = scheme == "pythilo" && url.host?.lowercased() == "playground"
        let isWeb = (scheme == "https" || scheme == "http") && url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "playground"
        guard isApp || isWeb, let fragment = url.fragment(percentEncoded: false) ?? url.fragment else { return nil }
        for part in fragment.split(separator: "&") {
            let pieces = part.split(separator: "=", maxSplits: 1)
            if pieces.count == 2, pieces[0] == "code" {
                return try decode(String(pieces[1]).removingPercentEncoding ?? String(pieces[1]))
            }
        }
        return nil
    }

    static func decode(_ payload: String) throws -> ShareSnapshot {
        guard payload.count <= payloadLimit * 11 / 10 else { throw Failure(message: "This share link holds more than Pythilo can open.") }
        var clean = payload.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        while clean.hasSuffix("=") { clean.removeLast() }
        guard !clean.isEmpty, clean.count % 4 != 1,
              clean.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw damaged
        }
        var standard = clean.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        guard let compressed = Data(base64Encoded: standard) else { throw damaged }
        let json = try inflate(compressed)
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { throw damaged }
        guard let version = object["v"] as? Int else { throw damaged }
        if version > Self.version { throw Failure(message: "This link was made by a newer Pythilo. Update the app.") }
        guard version == Self.version else { throw damaged }
        var files: [String: String] = [:]
        for (path, value) in object["files"] as? [String: Any] ?? [:] {
            guard let text = value as? String else { continue }
            let normal = try safePath(path)
            files[normal] = text
        }
        let pythonFiles = files.keys.filter { $0.hasSuffix(".py") }.sorted()
        let requested = object["main"] as? String
        guard let main = requested.flatMap({ files[$0] != nil ? $0 : nil }) ?? (files["main.py"] != nil ? "main.py" : pythonFiles.first) else {
            throw Failure(message: "This share link has no Python file to run.")
        }
        let rawName = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ShareSnapshot(name: rawName.isEmpty ? "shared-project" : String(rawName.prefix(80)), main: main, files: files)
    }

    private static let damaged = Failure(message: "This share link is damaged. Copy the entire link.")

    /// Relative, inside the project, and no hidden tool folders.
    private static func safePath(_ path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !parts.contains("."),
              !parts.contains(where: { $0 == ".git" || $0 == ".pythilo" }) else {
            throw Failure(message: "This share link has a file outside its project: \(path)")
        }
        return parts.joined(separator: "/")
    }

    // MARK: Writing a link

    /// The text files of a project folder, leaving out what is generated or private.
    static func of(project url: URL, main: String?) throws -> ShareSnapshot {
        var files: [String: String] = [:]
        var total = 0
        let skipped: Set<String> = [".git", ".pythilo", "__pycache__", "node_modules", ".venv", "venv", "dist", "build", ".DS_Store"]
        let root = url.resolvingSymlinksInPath().path
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
        while let item = walker?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if skipped.contains(item.lastPathComponent) {
                if values?.isDirectory == true { walker?.skipDescendants() }
                continue
            }
            guard values?.isDirectory != true else { continue }
            let full = item.resolvingSymlinksInPath().path
            guard full.hasPrefix(root + "/") else { continue }
            let path = String(full.dropFirst(root.count + 1))
            // .env files usually hold secrets; a link is public to whoever has it.
            if path.split(separator: "/").last.map({ $0.hasPrefix(".env") }) == true { continue }
            guard (values?.fileSize ?? 0) <= 256 * 1024,
                  let data = try? Data(contentsOf: item), let text = String(data: data, encoding: .utf8) else { continue }
            total += data.count
            if total > inflatedLimit { throw Failure(message: "This project is too large for a link. Share a live room instead.") }
            files[path] = text
        }
        let pythonFiles = files.keys.filter { $0.hasSuffix(".py") }.sorted()
        guard let entry = main.flatMap({ files[$0] != nil && $0.hasSuffix(".py") ? $0 : nil })
            ?? (files["main.py"] != nil ? "main.py" : pythonFiles.first) else {
            throw Failure(message: "A share link needs at least one Python file.")
        }
        return ShareSnapshot(name: url.lastPathComponent, main: entry, files: files)
    }

    func payload() throws -> String {
        // Keys sorted, as the website writes them, so the same files give the same link.
        let object: [String: Any] = ["v": Self.version, "name": name, "main": main, "files": files]
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let encoded = try Self.deflate(json).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard encoded.count <= Self.payloadLimit else {
            throw Failure(message: "This project is too large for a link. Share a live room instead.")
        }
        return encoded
    }

    func webLink() throws -> URL { URL(string: "\(Self.webOrigin)/playground/#code=\(try payload())")! }
    func appLink() throws -> URL { URL(string: "pythilo://playground/#code=\(try payload())")! }

    /// Writes the files into a new project and returns it.
    @MainActor
    func createProject(in store: ProjectStore) throws -> Project {
        let template = ProjectTemplate(id: "shared", title: name, summary: "", systemImage: "link", files: files)
        return try store.create(name: name, template: template)
    }

    // MARK: Raw DEFLATE

    /// Apple's ZLIB is raw DEFLATE (RFC 1951), without zlib's header, which is
    /// exactly what the website's fflate writes and reads.
    static func deflate(_ data: Data) throws -> Data {
        try process(data, operation: COMPRESSION_STREAM_ENCODE, limit: Int.max)
    }

    static func inflate(_ data: Data) throws -> Data {
        try process(data, operation: COMPRESSION_STREAM_DECODE, limit: inflatedLimit)
    }

    private static func process(_ input: Data, operation: compression_stream_operation, limit: Int) throws -> Data {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw damaged }
        defer { compression_stream_destroy(stream) }
        let size = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        var output = Data()
        return try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data in
            stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(buffer)
            stream.pointee.src_size = input.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = size
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: size - stream.pointee.dst_size)
                if output.count > limit { throw Failure(message: "This share link holds more than Pythilo can open.") }
                switch status {
                case COMPRESSION_STATUS_OK:
                    // All input used and nothing more came out: the data stops short.
                    if stream.pointee.src_size == 0, stream.pointee.dst_size == size { throw Failure(message: "This share link is cut short. Copy the entire link.") }
                    continue
                case COMPRESSION_STATUS_END: return output
                default: throw damaged
                }
            }
        }
    }
}
