import Foundation

/// `npm run <script>` and `npx esbuild`. A script is run when it is an esbuild
/// command, built in the app by `JSBundler`; anything that needs Node (vite,
/// webpack, next) says so instead of failing somewhere deep.
@MainActor
enum NpmScripts {
    struct Build {
        var entryPoints: [String] = []
        var outdir: String?
        var outfile: String?
        var minify = false
        var watch = false
        var sourcemap = false
        var format: String?
        var jsx: String?
        var loader: [String: String] = [:]
        var define: [String: String] = [:]
        var ignored: [String] = []

        var options: [String: Any] {
            var options: [String: Any] = [
                "entryPoints": entryPoints,
                "outdir": outdir ?? "dist",
                "minify": minify,
                "sourcemap": sourcemap,
                "mode": watch || !minify ? "development" : "production",
                "loader": loader,
                "define": define,
            ]
            if let outfile { options["outfile"] = outfile }
            if let format { options["format"] = format }
            if let jsx { options["jsx"] = jsx }
            return options
        }
    }

    static func handles(_ line: String) -> Bool {
        line == "npm run" || line.hasPrefix("npm run ") || line == "npm start" || line.hasPrefix("npx esbuild") || line.hasPrefix("esbuild ")
    }

    static func run(_ line: String, in model: WorkspaceModel) async {
        let session = model.session
        let words = GitTerminal.split(line)
        let directory = model.terminalDirectory
        do {
            var command: [String]
            if words.first == "npm" {
                let manifest = try manifest(in: directory)
                let scripts = manifest["scripts"] as? [String: String] ?? [:]
                let name = words.count > 2 ? words[2] : (words.dropFirst().first == "start" ? "start" : "")
                guard !name.isEmpty else {
                    let list = scripts.keys.sorted().map { "  \($0): \(scripts[$0] ?? "")" }.joined(separator: "\n")
                    session.noteTerminal(list.isEmpty ? "This package.json has no scripts.\n" : "Scripts:\n\(list)\n", kind: .stdout)
                    return
                }
                guard let script = scripts[name] else {
                    throw BundlerFailure("There is no script named \(name). " + (scripts.isEmpty ? "package.json has none." : "Try: \(scripts.keys.sorted().joined(separator: ", "))."))
                }
                command = GitTerminal.split(script)
            } else {
                command = words
            }
            if command.first == "npx" { command.removeFirst() }
            guard command.first == "esbuild" else {
                let tool = command.first ?? "this script"
                throw BundlerFailure("\(tool) needs Node, which no iPhone or iPad app can run. Pythilo builds with esbuild in the app: write the script as \"esbuild src/main.jsx --bundle --outdir=dist\".")
            }
            let build = try parse(Array(command.dropFirst()))
            await bundle(build, in: model)
            model.bundleWatch = build.watch ? build : nil
            if build.watch {
                session.noteTerminal("Rebuilding on every save while this project is open.\n", kind: .stdout)
            }
        } catch {
            session.noteTerminal("npm: \(error.localizedDescription)\n", kind: .stderr)
        }
    }

    /// esbuild's own command-line flags, the ones a browser bundle uses.
    static func parse(_ arguments: [String]) throws -> Build {
        var build = Build()
        for argument in arguments {
            let (flag, value) = argument.contains("=") ? (String(argument.split(separator: "=", maxSplits: 1)[0]), String(argument.split(separator: "=", maxSplits: 1)[1])) : (argument, "")
            switch flag {
            case "--bundle", "--platform", "--target", "--color", "--log-level": break
            case "--minify": build.minify = true
            case "--watch": build.watch = true
            case "--sourcemap": build.sourcemap = true
            case "--outdir": build.outdir = value
            case "--outfile": build.outfile = value
            case "--format": build.format = value
            case "--jsx": build.jsx = value
            default:
                if flag.hasPrefix("--loader:") {
                    build.loader[String(flag.dropFirst("--loader:".count))] = value
                } else if flag.hasPrefix("--define:") {
                    build.define[String(flag.dropFirst("--define:".count))] = value
                } else if argument.hasPrefix("-") {
                    build.ignored.append(argument)
                } else {
                    build.entryPoints.append(argument)
                }
            }
        }
        guard !build.entryPoints.isEmpty else { throw BundlerFailure("Name an entry file, such as esbuild src/main.jsx --bundle.") }
        return build
    }

    static func bundle(_ build: Build, in model: WorkspaceModel) async {
        let session = model.session
        let root = model.terminalDirectory
        if !build.ignored.isEmpty {
            session.noteTerminal("Ignored here: \(build.ignored.joined(separator: " "))\n", kind: .stdout)
        }
        do {
            let result = try await JSBundler.shared.build(build.options, in: root)
            session.noteTerminal("esbuild \(result.version), in the app\n", kind: .stdout)
            for warning in result.warnings { session.noteTerminal(warning, kind: .stdout) }
            guard result.ok else {
                for error in result.errors { session.noteTerminal(error, kind: .stderr) }
                session.noteTerminal("Build failed.\n", kind: .stderr)
                return
            }
            var lines: [String] = []
            for output in result.outputs {
                guard let target = BundlerFiles.inside(root, output.path) else { continue }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try output.data.write(to: target, options: .atomic)
                lines.append("  \(output.path.padding(toLength: max(output.path.count, 28), withPad: " ", startingAt: 0)) \(ByteCountFormatter.string(fromByteCount: Int64(output.data.count), countStyle: .file))")
            }
            session.noteTerminal(lines.joined(separator: "\n") + "\nBuilt in \(String(format: "%.2f", Double(result.milliseconds) / 1000)) s\n", kind: .stdout)
            model.reloadTree()
        } catch {
            session.noteTerminal("npm: \(error.localizedDescription)\n", kind: .stderr)
        }
    }

    static func manifest(in directory: URL) throws -> [String: Any] {
        let url = directory.appending(path: "package.json")
        guard let data = try? Data(contentsOf: url) else { throw BundlerFailure("There is no package.json here.") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BundlerFailure("package.json is not a JSON object.") }
        return object
    }
}
