import Foundation

/// Only catalog-pinned resources are accepted; interrupted transfers keep a bounded partial file.
enum PackDownloader {
    final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let url = request.url, allowed(url) else { return nil }
            return request
        }
    }

    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil else { return false }
        let host = url.host?.lowercased() ?? ""
        return host == "pythilo.com" || host == "www.pythilo.com" || host == "huggingface.co" ||
            host == "cdn-lfs.huggingface.co" || host == "cdn-lfs-us-1.hf.co" ||
            host == "us.aws.cdn.hf.co" ||
            host == "cas-bridge.xethub.hf.co"
    }

    static func fetch(_ pack: ContentPack, partial: URL,
                      progress: @escaping @Sendable (Int) async -> Void) async throws -> URL {
        try ContentInstaller.validate(pack)
        guard allowed(pack.url) else { throw ContentFailure.invalid("This download origin is not allowed.") }
        let fm = FileManager.default
        try fm.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        var offset = ((try? fm.attributesOfItem(atPath: partial.path)[.size]) as? NSNumber)?.intValue ?? 0
        if offset > pack.bytes { try fm.removeItem(at: partial); offset = 0 }
        if offset == pack.bytes { return partial }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: pack.url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, allowed(finalURL) else {
            throw ContentFailure.invalid("The download returned an invalid response.")
        }
        switch http.statusCode {
        case 200: offset = 0
        case 206:
            guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                  range == "bytes \(offset)-\(pack.bytes - 1)/\(pack.bytes)" else {
                throw ContentFailure.invalid("The server returned an incorrect resume range.")
            }
        case 416:
            try? fm.removeItem(at: partial)
            throw ContentFailure.invalid("The saved download could not be resumed. Tap Retry to start again.")
        default: throw ContentFailure.invalid("Download failed (HTTP \(http.statusCode)). Tap Retry when connected.")
        }
        let remaining = pack.bytes - offset
        if response.expectedContentLength >= 0, response.expectedContentLength != Int64(remaining) {
            throw ContentFailure.invalid("The download size differs from the catalog.")
        }
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }
        if offset == 0 { try output.truncate(atOffset: 0) }
        try output.seek(toOffset: UInt64(offset))
        var received = offset, block = Data()
        block.reserveCapacity(64 * 1024)
        await progress(received)
        for try await byte in stream {
            guard received < pack.bytes else { throw ContentFailure.invalid("The download exceeded its declared size.") }
            block.append(byte); received += 1
            if block.count == 64 * 1024 {
                try Task.checkCancellation()
                try output.write(contentsOf: block); block.removeAll(keepingCapacity: true)
                await progress(received)
            }
        }
        try Task.checkCancellation()
        if !block.isEmpty { try output.write(contentsOf: block) }
        try output.synchronize()
        await progress(received)
        guard received == pack.bytes else { throw ContentFailure.invalid("The connection ended before the download finished.") }
        return partial
    }
}
