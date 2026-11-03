import Foundation
import WebKit

/// esbuild, compiled to WebAssembly, in a web view no one sees. iOS runs no Node,
/// but a web view runs WebAssembly at full speed, so `npm run build` works here.
/// The page reads the project through pythilo-bundler://project/, which serves
/// nothing outside the project folder.
@MainActor
final class JSBundler: NSObject, WKScriptMessageHandler {
    static let shared = JSBundler()

    struct Output: Sendable {
        let path: String
        let data: Data
    }

    struct Result: Sendable {
        let ok: Bool
        let milliseconds: Int
        let version: String
        let outputs: [Output]
        let warnings: [String]
        let errors: [String]
    }

    private let files = BundlerFiles()
    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Error>?
    private var ready = false

    /// Whether the app bundle carries esbuild; `scripts/vendor-packages.py` fetches it.
    static var isAvailable: Bool {
        Bundle.main.url(forResource: "esbuild", withExtension: nil).map { FileManager.default.fileExists(atPath: $0.appending(path: "esbuild.wasm").path) } ?? false
    }

    func build(_ options: [String: Any], in root: URL) async throws -> Result {
        try await start()
        files.root = root
        guard let webView else { throw BundlerFailure("The bundler did not start.") }
        let value = try await webView.callAsyncJavaScript("return await pythiloBuild(options)", arguments: ["options": options], contentWorld: .page)
        guard let result = value as? [String: Any] else { throw BundlerFailure("The bundler gave no result.") }
        let outputs = (result["outputs"] as? [[String: Any]] ?? []).compactMap { item -> Output? in
            guard let path = item["path"] as? String, let text = item["base64"] as? String, let data = Data(base64Encoded: text) else { return nil }
            return Output(path: path, data: data)
        }
        return Result(
            ok: result["ok"] as? Bool ?? false,
            milliseconds: result["milliseconds"] as? Int ?? 0,
            version: result["version"] as? String ?? "",
            outputs: outputs,
            warnings: result["warnings"] as? [String] ?? [],
            errors: result["errors"] as? [String] ?? []
        )
    }

    private func start() async throws {
        if ready { return }
        guard Self.isAvailable else {
            throw BundlerFailure("This build of Pythilo has no esbuild. Run scripts/vendor-packages.py and build again.")
        }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: BundlerFiles.scheme)
        configuration.userContentController.add(self, name: "ready")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
        webView = view
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            view.load(URLRequest(url: URL(string: "\(BundlerFiles.scheme)://app/host.html")!))
        }
        ready = true
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let text = message.body as? String ?? ""
        if text.hasPrefix("error") {
            loaded?.resume(throwing: BundlerFailure("esbuild could not start: \(text)"))
        } else {
            loaded?.resume()
        }
        loaded = nil
    }
}

struct BundlerFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Serves the bundler page and esbuild from the app, and the project's files.
final class BundlerFiles: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    static let scheme = "pythilo-bundler"
    private let lock = NSLock()
    private var _root: URL?

    var root: URL? {
        get { lock.withLock { _root } }
        set { lock.withLock { _root = newValue } }
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host() else { return fail(task) }
        let path = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file: URL?
        switch host {
        case "app":
            let name = (path as NSString).lastPathComponent
            file = [Bundle.main.url(forResource: "Bundler", withExtension: nil), Bundle.main.url(forResource: "esbuild", withExtension: nil)]
                .compactMap { $0?.appending(path: name) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        case "project":
            file = root.flatMap { Self.inside($0, path) }
        default:
            file = nil
        }
        var isDirectory: ObjCBool = false
        guard let file, FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let data = try? Data(contentsOf: file) else { return fail(task) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": Self.type(of: file.pathExtension),
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// A project path, only if it stays inside the project.
    static func inside(_ root: URL, _ relative: String) -> URL? {
        guard !relative.split(separator: "/").contains("..") else { return nil }
        let candidate = root.appending(path: relative).standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        return candidate.path == base || candidate.path.hasPrefix(base + "/") ? candidate : nil
    }

    private func fail(_ task: any WKURLSchemeTask) {
        let response = HTTPURLResponse(url: task.request.url ?? URL(string: "\(Self.scheme)://missing")!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])!
        task.didReceive(response)
        task.didReceive(Data())
        task.didFinish()
    }

    private static func type(of ext: String) -> String {
        switch ext.lowercased() {
        case "wasm": "application/wasm"
        case "js", "mjs", "cjs", "jsx", "ts", "tsx": "text/javascript; charset=utf-8"
        case "html": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        default: "application/octet-stream"
        }
    }
}
