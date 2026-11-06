import SwiftUI

struct PackagesView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel
    @State private var name = ""
    @State private var installed: [(String, String)] = []
    @State private var bundled: [(String, String, Bool)] = []
    @State private var runningID: String?
    @State private var failure: String?

    private var session: RunSession { model.session }
    private var busy: Bool { session.isBusy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        TextField("Package name", text: $name)
                            .font(.system(size: 15, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
                            .accessibilityIdentifier("package-name")
                        Button(action: install) {
                            HStack {
                                if busy { ProgressView().controlSize(.small) }
                                Text("Install")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.onBlue)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.app)
                        .disabled(name.isEmpty || busy)
                        .accessibilityIdentifier("package-install")
                    }

                    if let failure {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(failure) could not be installed").font(.system(size: 14, weight: .bold))
                            Text("It may need compiled code, and iOS only runs code signed into the app. The Terminal has pip's full message. Nothing was changed.")
                                .font(.system(size: 14))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.dangerPanel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.dangerBorder, lineWidth: 1) }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("IN THIS PROJECT").sectionLabel()
                        VStack(spacing: 0) {
                            if installed.isEmpty {
                                Text("Nothing yet. Packages go in .pythilo/site-packages, so each project has its own.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.muted)
                                    .padding(13)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(installed, id: \.0) { package in
                                HStack(spacing: 8) {
                                    Text(package.0).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(package.1).font(.system(size: 13, design: .monospaced)).foregroundStyle(AppTheme.muted)
                                    Button {
                                        run("pip uninstall \(package.0)")
                                    } label: {
                                        Image(systemName: "trash").foregroundStyle(AppTheme.coralInk).frame(width: 40, height: 44)
                                    }
                                    .buttonStyle(.app)
                                    .disabled(busy)
                                    .accessibilityLabel("Remove \(package.0)")
                                }
                                .padding(.leading, 13)
                                .padding(.trailing, 6)
                                .frame(minHeight: 50)
                            }
                        }
                        .panelCard()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("BUNDLED WITH PYTHILO, WORK OFFLINE").sectionLabel()
                        VStack(spacing: 0) {
                            ForEach(bundled, id: \.0) { package in
                                HStack(spacing: 8) {
                                    Text(package.0).font(.system(size: 15))
                                    if package.2 {
                                        Text("compiled").font(.system(size: 11.5, weight: .bold)).foregroundStyle(AppTheme.amber)
                                    }
                                    Spacer()
                                    Text(package.1).font(.system(size: 13, design: .monospaced)).foregroundStyle(AppTheme.muted)
                                }
                                .padding(.horizontal, 13)
                                .frame(minHeight: 44)
                            }
                        }
                        .panelCard()
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background, ignoresSafeAreaEdges: [])
            .navigationTitle("Packages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear(perform: reload)
            .onChange(of: session.phase) { _, phase in
                guard phase == .idle, let id = runningID else { return }
                if session.lastOutcome?.id == id, session.lastOutcome?.code != 0, !name.isEmpty {
                    failure = name
                } else {
                    name = ""
                }
                runningID = nil
                reload()
            }
        }
    }

    private func install() {
        failure = nil
        run("pip install \(name)")
    }

    private func run(_ line: String) {
        guard !busy else { return }
        session.noteTerminal("$ \(line)\n", kind: .input)
        runningID = session.submit(
            ["kind": "shell", "line": line, "root": model.project.url.path, "cwd": model.project.url.path],
            label: line,
            channel: .terminal
        )
    }

    private func reload() {
        let site = model.project.url.appending(path: ".pythilo/site-packages")
        installed = Self.distributions(in: site).map { ($0.0, $0.1) }
        let packages = Bundle.main.bundleURL.appending(path: "app_packages")
        let visible: Set<String> = ["django", "flask", "numpy", "pytest", "requests", "starlette", "uvicorn", "jedi", "pip", "pyflakes"]
        bundled = Self.distributions(in: packages)
            .filter { visible.contains($0.0.lowercased()) }
            .map { ($0.0, $0.1, $0.0.lowercased() == "numpy") }
    }

    private static func distributions(in folder: URL) -> [(String, String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name -> (String, String)? in
            guard name.hasSuffix(".dist-info") else { return nil }
            let stem = name.dropLast(".dist-info".count)
            guard let dash = stem.lastIndex(of: "-") else { return nil }
            return (String(stem[..<dash]), String(stem[stem.index(after: dash)...]))
        }
        .sorted { $0.0.lowercased() < $1.0.lowercased() }
    }
}
