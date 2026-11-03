import Foundation

/// The commands a project's framework offers, for one tap in the terminal.
/// Found from the project's files, then from the list Django prints when
/// manage.py runs without a command.
struct ProjectCommands: Equatable, Sendable {
    enum Framework: String, Sendable {
        case django = "Django"
        case flask = "Flask"
        case asgi = "Uvicorn"
    }

    struct Command: Hashable, Identifiable, Sendable {
        let title: String
        let line: String
        var group = ""
        /// Starts a server, so its chip leads.
        var servesSite = false
        /// Needs a name or path typed after it, so the chip only fills the input.
        var needsArgument = false
        var id: String { line }
    }

    var framework: Framework?
    var featured: [Command] = []
    var all: [Command] = []

    static let none = ProjectCommands()

    private static let djangoFeatured = ["runserver", "migrate", "makemigrations", "createsuperuser", "test", "check"]
    private static let djangoArguments: Set<String> = [
        "startapp", "startproject", "sqlmigrate", "squashmigrations", "dumpdata", "loaddata",
        "makemessages", "compilemessages", "changepassword", "inspectdb", "sqlsequencereset", "help",
    ]

    /// What the project's files say it is. `djangoNames` are the commands Django
    /// itself listed, when it has.
    static func detect(root: URL, djangoNames: [(group: String, name: String)]) -> ProjectCommands {
        let manager = FileManager.default
        var result = ProjectCommands()
        if manager.fileExists(atPath: root.appending(path: "manage.py").path) {
            result.framework = .django
            let listed = djangoNames.isEmpty ? djangoFeatured.map { (group: "django", name: $0) } : djangoNames
            result.all = listed.map { group, name in
                Command(
                    title: name,
                    line: "python manage.py \(name)" + (djangoArguments.contains(name) ? " " : ""),
                    group: group,
                    servesSite: name == "runserver",
                    needsArgument: djangoArguments.contains(name)
                )
            }
            let names = Set(listed.map(\.name))
            result.featured = djangoFeatured.filter(names.contains).compactMap { name in result.all.first { $0.title == name } }
        } else if let module = module(in: root, containing: ["Flask("]) {
            result.framework = .flask
            result.featured = [
                Command(title: "run", line: "flask --app \(module) run", servesSite: true),
                Command(title: "routes", line: "flask --app \(module) routes"),
            ]
        } else if let module = module(in: root, containing: ["FastAPI(", "Starlette("]) {
            result.framework = .asgi
            result.featured = [Command(title: "uvicorn \(module):app", line: "uvicorn \(module):app", servesSite: true)]
        }
        let hasTests = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).contains { $0.hasPrefix("test_") && $0.hasSuffix(".py") }
            || manager.fileExists(atPath: root.appending(path: "tests").path)
        if hasTests, !result.featured.contains(where: { $0.title == "test" }) {
            result.featured.append(Command(title: "pytest", line: "pytest -q"))
        }
        if result.all.isEmpty { result.all = result.featured }
        return result
    }

    /// The module whose source creates the app, read from the usual entry files.
    private static func module(in root: URL, containing needles: [String]) -> String? {
        for name in ["app", "main", "hello", "wsgi", "asgi", "server"] {
            guard let text = try? String(contentsOf: root.appending(path: "\(name).py"), encoding: .utf8) else { continue }
            if needles.contains(where: text.contains) { return name }
        }
        return nil
    }

    /// The commands under "Available subcommands:", with the app each belongs to.
    static func djangoCommands(in output: String) -> [(group: String, name: String)]? {
        guard let start = output.range(of: "Available subcommands:", options: .backwards) else { return nil }
        var group = ""
        var found: [(group: String, name: String)] = []
        for line in output[start.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: /\[([A-Za-z0-9_]+)\]\s*/) {
                group = String(match.1)
            } else if let match = line.wholeMatch(of: /\s{4}([a-z][a-z0-9_]*)\s*/) {
                found.append((group, String(match.1)))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty, !found.isEmpty {
                break
            }
        }
        return found.count >= 3 ? found : nil
    }
}
