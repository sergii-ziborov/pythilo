import PythiloGit
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @Bindable var store: ProjectStore
    let onOpen: (Project) -> Void
    let onSettings: () -> Void
    @State private var showingNew = false
    @State private var showingClone = false
    @State private var showingImport = false
    @State private var failure: String?
    @State private var deleting: Project?
    @State private var renaming: Project?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        action("New", "plus", primary: true) { showingNew = true }
                            .accessibilityIdentifier("project-new")
                        action("Clone", "arrow.triangle.branch") { showingClone = true }
                        action("Import", "square.and.arrow.down") { showingImport = true }
                    }
                    if store.projects.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start with a project").font(.system(size: 17, weight: .semibold))
                            Text("A project is an ordinary folder. It also shows up in the Files app, and Python runs it right here on this device.")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelCard()
                    } else {
                        Text("RECENT").sectionLabel().padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8)], spacing: 8) {
                            ForEach(store.projects) { project in
                                row(project)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DownloadsLink() }
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                }
            }
            .onAppear(perform: store.refresh)
            .sheet(isPresented: $showingNew) {
                NewProjectSheet(store: store, onCreated: onOpen)
            }
            .sheet(isPresented: $showingClone) {
                CloneSheet(store: store, onCreated: onOpen)
            }
            .fileImporter(isPresented: $showingImport, allowedContentTypes: [.folder]) { result in
                do {
                    onOpen(try store.importFolder(from: try result.get()))
                } catch {
                    failure = error.localizedDescription
                }
            }
            .confirmationDialog(
                deleting.map { "Delete \($0.name)?" } ?? "",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let deleting { attempt { try store.delete(deleting) } }
                }
            } message: {
                Text("This removes the folder from this device.")
            }
            .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let renaming { attempt { try store.rename(renaming, to: renameText) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Could not do that", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { failure = error.localizedDescription }
    }

    private func action(_ title: String, _ symbol: String, primary: Bool = false, _ handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(primary ? AppTheme.onRun : AppTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(primary ? AppTheme.run : AppTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.app)
    }

    private func row(_ project: Project) -> some View {
        Button {
            onOpen(project)
        } label: {
            HStack(spacing: 12) {
                FileIconView(name: "", isDirectory: true, isOpen: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(ProjectStore.describe(project.url)).font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    Text("Edited \(project.modified.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .panelCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.app)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = project.name
                renaming = project
            }
            ShareLink(item: project.url) { Label("Share folder", systemImage: "square.and.arrow.up") }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = project }
        }
        .accessibilityIdentifier("project-\(project.name)")
    }
}

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: ProjectStore
    let onCreated: (Project) -> Void
    @State private var name = ""
    @State private var template = ProjectTemplate.blank.id
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("my-project", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("project-name")
                }
                Section("Start from") {
                    ForEach(ProjectTemplate.all) { item in
                        Button {
                            template = item.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemImage).frame(width: 24).foregroundStyle(AppTheme.blue)
                                VStack(alignment: .leading) {
                                    Text(item.title).foregroundStyle(AppTheme.primary)
                                    Text(item.summary).font(.footnote).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                if template == item.id { Image(systemName: "checkmark").foregroundStyle(AppTheme.blue) }
                            }
                        }
                        .accessibilityIdentifier("template-\(item.id)")
                    }
                }
                if let selected = ProjectTemplate.all.first(where: { $0.id == template }), !selected.requiredPacks.isEmpty {
                    Section("Packages for offline use") {
                        ForEach(selected.requiredPacks, id: \.self) { id in
                            if let pack = ContentStore.shared.catalog.pack(id) {
                                Text("\(pack.title) · \(ByteCountFormatter.string(fromByteCount: Int64(ContentStore.shared.missingBytes(id)), countStyle: .file)) remaining")
                            }
                        }
                        Text("Creating this project saves its code without downloading anything. Open Project downloads and tap Download project packages before going offline.")
                            .font(.footnote).foregroundStyle(AppTheme.secondary)
                    }
                }
                if let failure { Text(failure).foregroundStyle(AppTheme.coralInk) }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let selected = ProjectTemplate.all.first { $0.id == template } ?? .blank
                        do {
                            let project = try store.create(name: name.isEmpty ? selected.id : name, template: selected)
                            dismiss()
                            onCreated(project)
                        } catch {
                            failure = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("project-create")
                }
            }
        }
    }
}

struct CloneSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: ProjectStore
    let onCreated: (Project) -> Void
    @State private var address = ""
    @State private var username = ""
    @State private var token = ""
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("HTTPS address") {
                    TextField("https://github.com/you/repo.git", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Access token", text: $token)
                } header: {
                    Text("Private repository")
                } footer: {
                    Text("Leave empty for a public repository. A token stays in the Keychain, on this device only.")
                }
                if let failure { Text(failure).foregroundStyle(AppTheme.coralInk) }
            }
            .navigationTitle("Clone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Clone", action: clone).disabled(address.isEmpty)
                    }
                }
            }
        }
    }

    private func clone() {
        working = true
        failure = nil
        let credential = token.isEmpty ? nil : GitCredential(username: username.isEmpty ? "git" : username, token: token)
        Task {
            do {
                if !token.isEmpty {
                    try GitCredentialVault.save(address: address, username: username.isEmpty ? "git" : username, token: token)
                }
                let project = try await store.clone(address: address, credential: credential)
                dismiss()
                onCreated(project)
            } catch {
                failure = error.localizedDescription
            }
            working = false
        }
    }
}
