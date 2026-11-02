import PythiloGit
import SwiftUI

struct GitView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel
    @State private var tab = 0
    @State private var snapshot: GitSnapshot?
    @State private var commits: [GitCommitSummary] = []
    @State private var branches: [String] = []
    @State private var selection: Set<String> = []
    @State private var selectedDiff: String?
    @State private var diffText = ""
    @State private var message = ""
    @State private var status: String?
    @State private var working = false
    @State private var newBranch = ""
    @State private var remote = ""
    @State private var showingToken = false
    @State private var username = ""
    @State private var token = ""
    @AppStorage("pythilo.gitName") private var author = ""
    @AppStorage("pythilo.gitEmail") private var email = ""

    private var repository: ProjectRepository { model.repository }

    var body: some View {
        NavigationStack {
            Group {
                if repository.exists {
                    repositoryBody
                } else {
                    emptyBody
                }
            }
            .background(AppTheme.background, ignoresSafeAreaEdges: [])
            .navigationTitle("Git")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.refreshGit()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: reload)
                }
            }
            .onAppear(perform: reload)
            .alert("HTTPS token", isPresented: $showingToken) {
                TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Token", text: $token)
                Button("Save") {
                    if let address = snapshot?.remoteURL {
                        do {
                            try GitCredentialVault.save(address: address, username: username, token: token)
                            status = "Saved in the Keychain, on this device only."
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                    token = ""
                }
                Button("Cancel", role: .cancel) { token = "" }
            } message: {
                Text("Used only for this host. It never goes into the project.")
            }
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 34)).foregroundStyle(AppTheme.muted)
            Text("This project has no history yet").font(.system(size: 17, weight: .semibold))
            Text("Pythilo uses an ordinary .git folder, so the project stays a normal repository on a computer.")
                .font(.system(size: 14)).foregroundStyle(AppTheme.muted).multilineTextAlignment(.center)
            Button {
                attempt { try repository.initialize() }
            } label: {
                Text("Start a repository")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.onBlue)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("git-init")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var repositoryBody: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                Picker("View", selection: $tab) {
                    Text("Changes \(snapshot?.changes.count ?? 0)").tag(0)
                    Text("History").tag(1)
                    Text("Branches").tag(2)
                }
                .pickerStyle(.segmented)
                switch tab {
                case 0: changes
                case 1: history
                default: branchList
                }
                if let status {
                    Text(status).font(.system(size: 13)).foregroundStyle(AppTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(AppTheme.coral)
                Text(snapshot?.branch ?? "").font(.system(size: 17, weight: .bold, design: .monospaced))
                Spacer()
                if let ahead = snapshot?.ahead, let behind = snapshot?.behind {
                    Text("↑\(ahead) ↓\(behind)").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(AppTheme.muted)
                }
            }
            Text([snapshot?.remoteURL ?? "No remote", snapshot?.head.map { String($0.prefix(8)) }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
            if snapshot?.remoteURL != nil {
                HStack(spacing: 6) {
                    networkButton("Fetch") { credential in
                        try repository.fetch(credential: credential)
                        return "Fetched origin."
                    }
                    networkButton("Pull") { credential in
                        try repository.pull(credential: credential)
                    }
                    networkButton("Push") { credential in
                        try repository.push(credential: credential)
                    }
                    Button {
                        showingToken = true
                    } label: {
                        Image(systemName: "key").frame(width: 44, height: 44).background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("HTTPS token")
                }
                .padding(.top, 4)
            } else {
                HStack(spacing: 6) {
                    TextField("https://github.com/you/repo.git", text: $remote)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                    Button("Add") { attempt { try repository.setRemote(url: remote) } }
                        .disabled(remote.isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .panelCard()
    }

    private func networkButton(_ title: String, _ action: @escaping @Sendable (GitCredential?) throws -> String) -> some View {
        Button(title) {
            let credential = GitCredentialVault.credential(for: snapshot?.remoteURL)
            working = true
            status = "\(title)…"
            Task {
                do {
                    status = try await Task.detached { try action(credential) }.value
                } catch {
                    status = error.localizedDescription
                }
                working = false
                reload()
                model.reloadTree()
                model.reloadChangedBuffers()
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
        .buttonStyle(.plain)
        .disabled(working)
    }

    private var changes: some View {
        VStack(spacing: 12) {
            if snapshot?.changes.isEmpty != false {
                Label("Working tree is clean", systemImage: "checkmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.mint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot?.changes ?? []) { change in
                        changeRow(change)
                        if change.id != snapshot?.changes.last?.id { Rectangle().fill(AppTheme.border).frame(height: 1) }
                    }
                }
                .panelCard()
                if selectedDiff != nil {
                    ScrollView(.horizontal) {
                        DiffText(text: diffText).padding(10)
                    }
                    .frame(maxHeight: 280)
                    .panelCard()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if author.isEmpty || email.isEmpty {
                    TextField("Your name", text: $author).textContentType(.name).gitField()
                    TextField("Your email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).gitField()
                }
                HStack(spacing: 8) {
                    TextField("Commit message", text: $message).gitField().accessibilityIdentifier("git-message")
                    Button("Commit \(selection.count)", action: commit)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.onBlue)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12))
                        .buttonStyle(.plain)
                        .disabled(selection.isEmpty || message.isEmpty)
                        .accessibilityIdentifier("git-commit")
                }
            }
        }
    }

    private func changeRow(_ change: GitFileChange) -> some View {
        HStack(spacing: 9) {
            Button {
                if selection.contains(change.path) { selection.remove(change.path) } else { selection.insert(change.path) }
            } label: {
                Image(systemName: selection.contains(change.path) ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(selection.contains(change.path) ? AppTheme.blue : AppTheme.muted)
                    .frame(width: 34, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Include \(change.path)")
            Button {
                selectedDiff = change.path
                diffText = (try? repository.diff(path: change.path)) ?? ""
            } label: {
                HStack(spacing: 8) {
                    FileIconView(name: (change.path as NSString).lastPathComponent)
                    Text(change.path).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.head)
                    Spacer()
                    Text(change.kind.rawValue).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(change.kind == .deleted ? AppTheme.coralInk : change.kind == .modified ? AppTheme.amber : AppTheme.mint)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 12)
        .padding(.leading, 4)
        .background(selectedDiff == change.path ? AppTheme.selection : Color.clear)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commits.isEmpty {
                Text("No commits yet.").font(.system(size: 14)).foregroundStyle(AppTheme.muted).padding(14)
            }
            ForEach(commits) { commit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(commit.message).font(.system(size: 15)).lineLimit(2)
                    Text("\(commit.shortID) · \(commit.author) · \(commit.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }
        }
        .panelCard()
    }

    private var branchList: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                ForEach(branches, id: \.self) { branch in
                    Button {
                        model.saveAll()
                        attempt {
                            try repository.switchBranch(branch)
                            model.reloadTree()
                            model.reloadChangedBuffers()
                        }
                    } label: {
                        HStack {
                            Text(branch).font(.system(size: 14, design: .monospaced))
                            Spacer()
                            if branch == snapshot?.branch { Image(systemName: "checkmark").foregroundStyle(AppTheme.blue) }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .panelCard()
            HStack(spacing: 8) {
                TextField("New branch", text: $newBranch).textInputAutocapitalization(.never).autocorrectionDisabled().gitField()
                Button("Create") {
                    attempt { try repository.createBranch(newBranch) }
                    newBranch = ""
                }
                .disabled(newBranch.isEmpty)
            }
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do {
            try action()
            status = nil
        } catch {
            status = error.localizedDescription
        }
        reload()
    }

    private func commit() {
        model.saveAll()
        attempt {
            try repository.stage(Array(selection))
            let commit = try repository.commit(message: message, author: author, email: email)
            status = "Committed \(commit.shortID)."
        }
        status = status ?? "Committed."
        message = ""
        selection = []
        selectedDiff = nil
    }

    private func reload() {
        guard repository.exists else {
            snapshot = nil
            return
        }
        snapshot = try? repository.snapshot()
        commits = (try? repository.history()) ?? []
        branches = (try? repository.branches()) ?? []
        let changed = Set(snapshot?.changes.map(\.path) ?? [])
        if selection.isEmpty { selection = changed } else { selection.formIntersection(changed) }
        model.refreshGit()
    }
}

private struct DiffText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(text.components(separatedBy: "\n").prefix(600).enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(line.hasPrefix("+") ? AppTheme.mint : line.hasPrefix("-") ? AppTheme.coralInk : line.hasPrefix("@@") ? AppTheme.blue : AppTheme.secondary)
            }
        }
    }
}

private extension View {
    func gitField() -> some View {
        padding(.horizontal, 12)
            .frame(height: 48)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
    }
}
