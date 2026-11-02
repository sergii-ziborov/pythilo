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
                    TextField("Name", text: $gitName).textContentType(.name)
                    TextField("Email", text: $gitEmail).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    LabeledContent("HTTPS tokens", value: "\(GitCredentialVault.count()) in Keychain")
                }
                Section("Python") {
                    LabeledContent("Version", value: RunSession.shared.pythonVersion ?? "Starting")
                    NavigationLink("What runs here") { LimitsView() }
                    NavigationLink("Licenses") { LicensesView() }
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
