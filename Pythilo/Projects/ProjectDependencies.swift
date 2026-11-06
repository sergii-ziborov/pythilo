import Foundation

/// Migrates existing projects and discovers common native imports without executing code.
enum ProjectDependencies {
    static let modules: [String: String] = [
        "torch": "runtime-torch", "functorch": "runtime-torch", "numpy": "runtime-numpy",
        "sympy": "runtime-math", "mpmath": "runtime-math", "networkx": "runtime-math",
        "django": "runtime-web", "flask": "runtime-web", "fastapi": "runtime-web",
        "pydantic": "runtime-web", "pydantic_core": "runtime-web", "starlette": "runtime-web",
        "uvicorn": "runtime-web", "httpx": "runtime-web",
        "pythilo_finetune": "runtime-torch", "finetune_projects": "runtime-torch",
    ]

    @MainActor @discardableResult
    static func refresh(_ project: Project) -> [String] {
        let fm = FileManager.default
        var packs = Set(project.requiredPacks)
        let ignored = Set(["node_modules", ".git", ".pythilo", "__pycache__", "assets", "artifacts", ".venv", "venv"])
        guard let iterator = fm.enumerator(at: project.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return Array(packs).sorted() }
        let pattern = try? NSRegularExpression(pattern: "(?m)^\\s*(?:from\\s+([A-Za-z_][A-Za-z_0-9]*)[.\\s]|import\\s+([^\\n;#]+))")
        var bytes = 0, count = 0
        while let file = iterator.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if values?.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if values?.isDirectory == true {
                if ignored.contains(file.lastPathComponent) { iterator.skipDescendants() }
                continue
            }
            guard file.pathExtension == "py" || file.lastPathComponent == "requirements.txt",
                  let size = values?.fileSize, size <= 512 * 1024, bytes + size <= 2 * 1024 * 1024, count < 200,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            count += 1; bytes += size
            var imports = Set<String>()
            if file.lastPathComponent == "requirements.txt" {
                for line in text.split(separator: "\n") {
                    let name = line.trimmingCharacters(in: .whitespaces).prefix { $0.isLetter || $0.isNumber || "_-".contains($0) }
                    if !name.isEmpty { imports.insert(name.lowercased().replacingOccurrences(of: "-", with: "_")) }
                }
            } else {
                let source = text as NSString
                for match in pattern?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? [] {
                    if match.range(at: 1).location != NSNotFound { imports.insert(source.substring(with: match.range(at: 1))) }
                    else {
                        for item in source.substring(with: match.range(at: 2)).split(separator: ",") {
                            if let name = item.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == "." || $0.isWhitespace }).first { imports.insert(String(name)) }
                        }
                    }
                }
            }
            for name in imports {
                let local = fm.fileExists(atPath: project.url.appending(path: "\(name).py").path) || fm.fileExists(atPath: project.url.appending(path: "\(name)/__init__.py").path)
                if let pack = modules[name], !local || name == "pythilo_finetune" || name == "finetune_projects" { packs.insert(pack) }
                if name == "pythilo_finetune" || name == "finetune_projects" {
                    packs.formUnion(["assets-finetune-data", "assets-bert-weights"])
                }
            }
        }
        let result = packs.sorted()
        if result != project.requiredPacks.sorted(), let data = try? JSONEncoder().encode(result) {
            try? data.write(to: project.url.appending(path: "pythilo-packages.json"), options: .atomic)
        }
        return result
    }
}
