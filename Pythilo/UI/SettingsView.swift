import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pythilo.drawerSide") private var drawerSide = DrawerSide.left.rawValue
    @AppStorage("pythilo.drawerSwipe") private var drawerSwipe = true
    @AppStorage("pythilo.hideStatusBar") private var hideStatusBar = true
    @AppStorage("pythilo.editorFontSize") private var fontSize = 14.0
    @AppStorage("pythilo.appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("pythilo.gitName") private var gitName = ""
    @AppStorage("pythilo.gitEmail") private var gitEmail = ""
    @AppStorage("pythilo.roomName") private var roomName = ""
    @AppStorage("pythilo.githubLogin") private var githubLogin = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    Picker("File drawer side", selection: $drawerSide) {
                        ForEach(DrawerSide.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Swipe from the edge opens it", isOn: $drawerSwipe)
                    Toggle("Hide status bar in the editor", isOn: $hideStatusBar)
                    Stepper("Code size \(Int(fontSize)) pt", value: $fontSize, in: 10...24)
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Section("Git") {
                    NavigationLink { GitHubAccountView() } label: {
                        LabeledContent {
                            Text(githubLogin.isEmpty ? "Not signed in" : "@\(githubLogin)")
                        } label: {
                            Label("GitHub account", systemImage: "person.crop.circle")
                        }
                    }
                    .accessibilityIdentifier("settings-github")
                    TextField("Name", text: $gitName).textContentType(.name)
                    TextField("Email", text: $gitEmail).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    LabeledContent("HTTPS tokens", value: "\(GitCredentialVault.count()) in Keychain")
                }
                Section {
                    TextField("Your name", text: $roomName).textContentType(.givenName)
                    LabeledContent("Relay", value: PlaygroundRelayConfiguration.origin?.host() ?? "Not set up")
                } header: {
                    Text("Shared rooms")
                } footer: {
                    Text("Others see it beside your cursor, and this device as \(PlaygroundRuntimeHost.deviceName).")
                }
                Section("Python") {
                    LabeledContent("Version", value: RunSession.shared.pythonVersion ?? "Starting")
                    NavigationLink("What runs here") { LimitsView() }
                    NavigationLink("Licenses") { LicensesView() }
                }
                Section {
                    NavigationLink { AboutView() } label: {
                        HStack(spacing: 12) {
                            AppMark(size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("About Pythilo").font(.system(size: 16, weight: .semibold))
                                Text("Version \(AppInfo.version)").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("settings-about")
                    LinkRow(title: "Website", detail: "pythilo.com", systemImage: "globe", url: AppInfo.website)
                    LinkRow(title: "User guide", systemImage: "book.pages", url: AppInfo.guide)
                    LinkRow(title: "Help and support", systemImage: "questionmark.circle", url: AppInfo.support)
                    LinkRow(title: "Contact", detail: AppInfo.supportEmail, systemImage: "envelope", url: AppInfo.mail)
                } header: {
                    Text("About")
                }
                Section {
                    LinkRow(title: "Rate Pythilo", systemImage: "star", url: AppInfo.review)
                    ShareLink(item: AppInfo.appStore, subject: Text("Pythilo"), message: Text("Real Python on iPhone and iPad.")) {
                        Label("Share Pythilo", systemImage: "square.and.arrow.up")
                    }
                    LinkRow(title: "Report a bug", detail: "GitHub", systemImage: "ladybug", url: AppInfo.issues)
                } footer: {
                    Text("No account, analytics or advertising. Projects stay on this device unless you share them.")
                }
                Section("Legal") {
                    LinkRow(title: "Privacy policy", systemImage: "hand.raised", url: AppInfo.privacy)
                    LinkRow(title: "Terms of use", systemImage: "doc.text", url: AppInfo.terms)
                    LinkRow(title: "Acceptable use", systemImage: "checkmark.shield", url: AppInfo.acceptableUse)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

struct LimitsView: View {
    var body: some View {
        List {
            Section("Runs on this device") {
                Text("CPython 3.14, with its standard library")
                Text("Your projects, tests and the debugger")
                Text("Local web servers: Django, Flask, Starlette on Uvicorn")
                Text("Notebooks, with cells that share one namespace")
                Text("Pure-Python packages from PyPI, per project")
                Text("NumPy, bundled and compiled for iOS")
            }
            Section("Not possible on iOS") {
                Text("Starting other programs, subprocesses or multiprocessing")
                Text("Installing compiled packages that Pythilo does not bundle")
                Text("Docker and database servers")
            }
            Section("Worth knowing") {
                Text("All projects share one Python process. Pythilo resets it between runs, but that is cleanup and not a security boundary. Only run code you trust.")
                Text("A compiled call that never returns cannot be stopped from inside the app. Your files are already saved, so closing the app loses nothing.")
                Text("Servers stop when iOS suspends the app in the background.")
            }
        }
        .navigationTitle("What runs here")
    }
}

struct LicensesView: View {
    private var packages: [String] {
        let folder = Bundle.main.bundleURL.appending(path: "app_packages")
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".dist-info") }
            .map { String($0.dropLast(".dist-info".count)) }
            .sorted()
    }

    var body: some View {
        List {
            Section("Runtime") {
                Text("CPython 3.14.10, Python Software Foundation License")
                Text("Python-Apple-support by BeeWare, BSD 3-Clause")
                Text("libgit2 1.9.7, GPLv2 with linking exception")
            }
            Section("Bundled Python packages") {
                ForEach(packages, id: \.self) { Text($0).font(.system(size: 14, design: .monospaced)) }
            }
            Section {
                Text("Each package keeps its license file inside the app bundle, in its .dist-info folder.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Licenses")
    }
}

/// Where Pythilo lives outside the app. Every page here is on the public website.
enum AppInfo {
    static let appStoreID = "6829637526"
    static let supportEmail = "support@pythilo.com"
    static let website = URL(string: "https://pythilo.com/")!
    static let guide = URL(string: "https://pythilo.com/guide/")!
    static let support = URL(string: "https://pythilo.com/support/")!
    static let blog = URL(string: "https://pythilo.com/blog/")!
    static let labs = URL(string: "https://pythilo.com/labs/")!
    static let privacy = URL(string: "https://pythilo.com/legal/privacy/")!
    static let terms = URL(string: "https://pythilo.com/legal/terms/")!
    static let acceptableUse = URL(string: "https://pythilo.com/legal/acceptable-use/")!
    static let licenses = URL(string: "https://pythilo.com/legal/licenses/")!
    static let source = URL(string: "https://github.com/sergii-ziborov/pythilo")!
    static let issues = URL(string: "https://github.com/sergii-ziborov/pythilo/issues/new")!
    static let mail = URL(string: "mailto:\(supportEmail)?subject=Pythilo%20\(version.replacingOccurrences(of: " ", with: "%20"))")!
    static let appStore = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
    static let review = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!

    static var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    /// "1.0 (31)"
    static var version: String { "\(shortVersion) (\(build))" }
    static var copyright: String { Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2026 Serhii Ziborov" }
}

/// The app icon, drawn small.
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image("PythiloMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(AppTheme.border, lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

/// A row that opens a page or a mail draft outside the app.
struct LinkRow: View {
    let title: String
    var detail: String?
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage).foregroundStyle(AppTheme.primary)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail).font(.system(size: 14)).foregroundStyle(AppTheme.muted).lineLimit(1)
                }
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint(url.scheme == "mailto" ? "Writes an email" : "Opens \(url.host() ?? "the page")")
    }
}

struct AboutView: View {
    private var counts: (lessons: Int, courses: Int, tasks: Int, labs: Int) {
        let library = CourseLibrary.shared
        let paths = library.paths
        return (paths.reduce(0) { $0 + $1.lessons.count }, paths.count, library.interview?.lessons.count ?? 0, LabCatalog.all.count)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    AppMark(size: 88)
                    Text("Pythilo").font(.system(size: 26, weight: .bold))
                    Text("Real Python on iPhone and iPad").font(.system(size: 15)).foregroundStyle(AppTheme.secondary)
                    Text("Version \(AppInfo.version)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("about-version")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section("In this app") {
                LabeledContent("Python", value: RunSession.shared.pythonVersion.map { "CPython \($0)" } ?? "Starting")
                LabeledContent("Lessons", value: "\(counts.lessons) in \(counts.courses) courses")
                if counts.tasks > 0 { LabeledContent("Interview tasks", value: "\(counts.tasks)") }
                LabeledContent("Labs", value: "\(counts.labs)")
                LabeledContent("Runs", value: "On this device, offline after downloads")
            }
            Section("Pythilo online") {
                LinkRow(title: "Website", detail: "pythilo.com", systemImage: "globe", url: AppInfo.website)
                LinkRow(title: "User guide", systemImage: "book.pages", url: AppInfo.guide)
                LinkRow(title: "Labs in the browser", systemImage: "testtube.2", url: AppInfo.labs)
                LinkRow(title: "Blog", systemImage: "newspaper", url: AppInfo.blog)
                LinkRow(title: "Pythilo on the App Store", systemImage: "bag", url: AppInfo.appStore)
                LinkRow(title: "Source code", detail: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: AppInfo.source)
            }
            Section("Help") {
                LinkRow(title: "Help and support", systemImage: "questionmark.circle", url: AppInfo.support)
                LinkRow(title: "Email support", detail: AppInfo.supportEmail, systemImage: "envelope", url: AppInfo.mail)
                LinkRow(title: "Report a bug", detail: "GitHub", systemImage: "ladybug", url: AppInfo.issues)
                LinkRow(title: "Rate Pythilo", systemImage: "star", url: AppInfo.review)
            }
            Section {
                LinkRow(title: "Privacy policy", systemImage: "hand.raised", url: AppInfo.privacy)
                LinkRow(title: "Terms of use", systemImage: "doc.text", url: AppInfo.terms)
                LinkRow(title: "Acceptable use", systemImage: "checkmark.shield", url: AppInfo.acceptableUse)
                LinkRow(title: "Third-party licenses", systemImage: "list.bullet.rectangle", url: AppInfo.licenses)
            } header: {
                Text("Legal")
            } footer: {
                Text("\(AppInfo.copyright)\nPythilo collects no analytics and shows no advertising.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
