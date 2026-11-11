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
    @State private var query = ""
    @AppStorage("pythilo.projectFilter") private var filter = ""
    @AppStorage("pythilo.projectSort") private var sort = ProjectSort.recent.rawValue
    @State private var categorizing: Project?
    @State private var categoryText = ""
    @State private var renamingCategory: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        action("New", "plus", primary: true) { showingNew = true }
                            .accessibilityIdentifier("project-new")
                        action("Clone", "arrow.triangle.branch") { showingClone = true }
                            .accessibilityIdentifier("project-clone")
                        action("Import", "square.and.arrow.down") { showingImport = true }
                            .accessibilityIdentifier("project-import")
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
                        if store.projects.count > 1 { filterBar }
                        let groups = groupedProjects
                        if groups.isEmpty {
                            Text(query.isEmpty ? "No projects in this category." : "No projects match \u{201C}\(query)\u{201D}.")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.secondary)
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("projects-empty-filter")
                        }
                        ForEach(groups, id: \.title) { group in
                            Text(group.title.uppercased()).sectionLabel().padding(.top, 4)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8)], spacing: 8) {
                                ForEach(group.projects) { project in
                                    row(project)
                                }
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
            .searchable(text: $query, prompt: "Search projects")
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
            .alert(
                deleting.map { "Delete \($0.name)?" } ?? "Delete project?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                presenting: deleting
            ) { project in
                Button("Delete", role: .destructive) {
                    attempt { try store.delete(project) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the folder from this device.")
            }
            .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let renaming { attempt { try store.rename(renaming, to: renameText) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New category", isPresented: Binding(get: { categorizing != nil }, set: { if !$0 { categorizing = nil } })) {
                TextField("Category, for example Work", text: $categoryText)
                Button("Add") {
                    if let categorizing { store.setCategory(categoryText, for: categorizing) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(categorizing.map { "Put \($0.name) in a new category." } ?? "")
            }
            .alert("Rename category", isPresented: Binding(get: { renamingCategory != nil }, set: { if !$0 { renamingCategory = nil } })) {
                TextField("Name", text: $categoryText)
                Button("Rename") {
                    if let renamingCategory {
                        store.renameCategory(renamingCategory, to: categoryText)
                        if filter == renamingCategory { filter = categoryText.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
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

    // MARK: Filtering

    private struct Group { let title: String; let projects: [Project] }
    private static let noCategory = "\u{1}none"

    private var sorted: [Project] {
        switch ProjectSort(rawValue: sort) ?? .recent {
        case .recent: store.projects
        case .name: store.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .kind: store.projects.sorted {
            let a = ProjectStore.describe($0.url), b = ProjectStore.describe($1.url)
            return a == b ? $0.modified > $1.modified : a < b
        }
        }
    }

    private func matches(_ project: Project) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return project.name.localizedCaseInsensitiveContains(text)
            || ProjectStore.describe(project.url).localizedCaseInsensitiveContains(text)
            || (store.category(of: project)?.localizedCaseInsensitiveContains(text) ?? false)
    }

    private var groupedProjects: [Group] {
        let names = store.categoryNames
        let visible = sorted.filter(matches)
        if !filter.isEmpty {
            let chosen = visible.filter {
                filter == Self.noCategory ? store.category(of: $0) == nil : store.category(of: $0) == filter
            }
            let title = filter == Self.noCategory ? "No category" : filter
            return chosen.isEmpty ? [] : [Group(title: title, projects: chosen)]
        }
        // Everything: one section per category, then the rest, so a long list has structure.
        guard !names.isEmpty else {
            return visible.isEmpty ? [] : [Group(title: sort == ProjectSort.recent.rawValue ? "Recent" : "Projects", projects: visible)]
        }
        var groups = names.compactMap { name -> Group? in
            let items = visible.filter { store.category(of: $0) == name }
            return items.isEmpty ? nil : Group(title: name, projects: items)
        }
        let rest = visible.filter { store.category(of: $0) == nil }
        if !rest.isEmpty { groups.append(Group(title: "No category", projects: rest)) }
        return groups
    }

    private var filterBar: some View {
        let names = store.categoryNames
        let uncategorized = store.projects.filter { store.category(of: $0) == nil }.count
        return HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All · \(store.projects.count)", systemImage: "square.grid.2x2", id: "")
                    ForEach(names, id: \.self) { name in
                        chip("\(name) · \(store.projects.filter { store.category(of: $0) == name }.count)", systemImage: "folder", id: name)
                            .contextMenu {
                                Button("Rename category", systemImage: "pencil") { categoryText = name; renamingCategory = name }
                                Button("Remove category", systemImage: "folder.badge.minus", role: .destructive) {
                                    store.removeCategory(name)
                                    if filter == name { filter = "" }
                                }
                            }
                    }
                    if !names.isEmpty && uncategorized > 0 {
                        chip("No category · \(uncategorized)", systemImage: "tray", id: Self.noCategory)
                    }
                }
            }
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(ProjectSort.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(width: 40, height: 36)
                    .background(AppTheme.raised, in: Capsule())
            }
            .accessibilityLabel("Sort projects")
            .accessibilityIdentifier("projects-sort")
        }
        .onAppear {
            // A category that no longer has projects should not leave the list empty.
            if !filter.isEmpty, filter != Self.noCategory, !names.contains(filter) { filter = "" }
        }
    }

    private func chip(_ title: String, systemImage: String, id: String) -> some View {
        let selected = filter == id
        return Button {
            filter = selected && !id.isEmpty ? "" : id
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(selected ? AppTheme.onBlue : AppTheme.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(selected ? AppTheme.blue : AppTheme.panel, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : AppTheme.border))
        }
        .buttonStyle(.app)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id.isEmpty ? "projects-filter-all" : "projects-filter-\(id)")
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
                    Text([ProjectStore.describe(project.url), store.category(of: project)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(AppTheme.muted).lineLimit(1)
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
            Menu {
                ForEach(store.categoryNames, id: \.self) { name in
                    Button {
                        store.setCategory(name, for: project)
                    } label: {
                        if store.category(of: project) == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
                Button("New category…", systemImage: "folder.badge.plus") {
                    categoryText = ""
                    categorizing = project
                }
                if store.category(of: project) != nil {
                    Button("Remove from category", systemImage: "folder.badge.minus") { store.setCategory(nil, for: project) }
                }
            } label: {
                Label("Category", systemImage: "folder")
            }
            ShareLink(item: project.url) { Label("Share folder", systemImage: "square.and.arrow.up") }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = project }
        }
        .accessibilityIdentifier("project-\(project.name)")
    }
}

enum ProjectSort: String, CaseIterable, Identifiable {
    case recent, name, kind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recently edited"
        case .name: "Name"
        case .kind: "Kind"
        }
    }
    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .name: "textformat"
        case .kind: "square.stack.3d.up"
        }
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
    enum Source: String, CaseIterable, Identifiable {
        case search, mine, address
        var id: String { rawValue }
        var title: String {
            switch self {
            case .search: "Search"
            case .mine: "My repos"
            case .address: "Address"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let store: ProjectStore
    let onCreated: (Project) -> Void
    @AppStorage("pythilo.githubLogin") private var githubLogin = ""
    @State private var source = Source.search
    @State private var address = ""
    @State private var username = ""
    @State private var token = ""
    @State private var working: String?
    @State private var failure: String?

    @State private var query = ""
    @State private var sort = GitHubSort.stars
    @State private var results: [GitHubRepository] = []
    @State private var total = 0
    @State private var searching = false
    @State private var searchFailure: String?

    @State private var mine: [GitHubRepository] = []
    @State private var mineFilter = ""
    @State private var loadingMine = false
    @State private var mineFailure: String?
    @State private var showingAccount = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("clone-source")
                if let failure {
                    Text(failure)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.coralInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                switch source {
                case .search: searchPane
                case .mine: minePane
                case .address: addressPane
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Clone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if source == .address {
                    ToolbarItem(placement: .confirmationAction) {
                        if working != nil {
                            ProgressView()
                        } else {
                            Button("Clone") { clone(address, credential: typedCredential, saveTyped: true) }.disabled(address.isEmpty)
                        }
                    }
                }
            }
            .overlay {
                if let working {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Cloning \(working)…").font(.system(size: 15, weight: .semibold))
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("clone-progress")
                }
            }
            .sheet(isPresented: $showingAccount) {
                NavigationStack { GitHubAccountView(showsDone: true) }
            }
            .onChange(of: githubLogin) { _, _ in mine = []; if source == .mine { Task { await loadMine() } } }
        }
    }

    // MARK: Search

    private var searchPane: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                    TextField("Search GitHub, for example django blog", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                        .accessibilityIdentifier("clone-search-field")
                    if searching { ProgressView() }
                }
                Picker("Sort", selection: $sort) {
                    ForEach(GitHubSort.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("clone-search-sort")
            } footer: {
                Text("GitHub syntax works too: language:python stars:>500 user:psf")
            }
            if let searchFailure {
                Text(searchFailure).foregroundStyle(AppTheme.coralInk)
            }
            if !results.isEmpty {
                Section {
                    ForEach(results) { repository in repositoryRow(repository) }
                } header: {
                    Text("\(total.formatted()) repositories")
                }
            } else if !searching && !query.isEmpty && searchFailure == nil {
                Text("Press Search to look on GitHub.").foregroundStyle(AppTheme.muted)
            }
        }
        .task(id: "\(query)|\(sort.rawValue)") {
            // Search as you type, after a short pause.
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        searchFailure = nil
        defer { searching = false }
        do {
            let page = try await GitHubClient.search(text, sort: sort)
            guard text == query.trimmingCharacters(in: .whitespaces) else { return }
            results = page.items
            total = page.total
            if page.items.isEmpty { searchFailure = "Nothing on GitHub matches \u{201C}\(text)\u{201D}." }
        } catch is CancellationError {
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            searchFailure = error.localizedDescription
        }
    }

    // MARK: My repositories

    @ViewBuilder
    private var minePane: some View {
        if githubLogin.isEmpty || GitHubClient.credential == nil {
            VStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 40)).foregroundStyle(AppTheme.blue)
                Text("Sign in to GitHub").font(.system(size: 18, weight: .semibold))
                Text("Save your GitHub account once to see all your repositories here, private ones included, and to push without typing a token again.")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingAccount = true
                } label: {
                    Text("Add GitHub account").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.onBlue)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.app)
                .accessibilityIdentifier("clone-add-account")
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease").foregroundStyle(AppTheme.muted)
                        TextField("Filter your repositories", text: $mineFilter)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("clone-mine-filter")
                    }
                } footer: {
                    Text("Signed in as @\(githubLogin). Change the account in Settings.")
                }
                if let mineFailure { Text(mineFailure).foregroundStyle(AppTheme.coralInk) }
                if loadingMine && mine.isEmpty {
                    HStack { ProgressView(); Text("Loading your repositories…").foregroundStyle(AppTheme.muted) }
                }
                let shown = mine.filter {
                    mineFilter.isEmpty || $0.fullName.localizedCaseInsensitiveContains(mineFilter)
                        || ($0.summary?.localizedCaseInsensitiveContains(mineFilter) ?? false)
                        || ($0.language?.localizedCaseInsensitiveContains(mineFilter) ?? false)
                }
                if !shown.isEmpty {
                    Section("\(shown.count) repositories · \(shown.filter(\.isPrivate).count) private") {
                        ForEach(shown) { repository in repositoryRow(repository) }
                    }
                }
            }
            .refreshable { await loadMine() }
            .task { if mine.isEmpty { await loadMine() } }
        }
    }

    private func loadMine() async {
        guard let token = GitHubClient.token else { return }
        loadingMine = true
        mineFailure = nil
        defer { loadingMine = false }
        do { mine = try await GitHubClient.repositories(token: token) } catch {
            mineFailure = error.localizedDescription
        }
    }

    // MARK: Address

    private var typedCredential: GitCredential? {
        if !token.isEmpty { return GitCredential(username: username.isEmpty ? "git" : username, token: token) }
        return GitCredentialVault.credential(for: address)
    }

    private var addressPane: some View {
        Form {
            Section("HTTPS address") {
                TextField("https://github.com/you/repo.git", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("clone-address")
            }
            Section {
                TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Access token", text: $token)
            } header: {
                Text("Private repository")
            } footer: {
                Text(githubLogin.isEmpty
                    ? "Leave empty for a public repository. A token stays in the Keychain, on this device only."
                    : "Leave empty to use your GitHub account (@\(githubLogin)) for github.com. A token stays in the Keychain, on this device only.")
            }
        }
    }

    // MARK: Rows and cloning

    private func repositoryRow(_ repository: GitHubRepository) -> some View {
        Button {
            clone(repository.cloneURL, credential: GitHubClient.credential, saveTyped: false, name: repository.fullName)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: repository.owner.avatarURL.map { URL(string: "\($0.absoluteString)&s=80") ?? $0 }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.square.fill").resizable().foregroundStyle(AppTheme.raised)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(repository.fullName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                            .lineLimit(2)
                        if repository.isPrivate {
                            Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(AppTheme.amber)
                                .accessibilityLabel("Private")
                        }
                    }
                    if let summary = repository.summary, !summary.isEmpty {
                        Text(summary).font(.system(size: 13)).foregroundStyle(AppTheme.secondary).lineLimit(2)
                    }
                    HStack(spacing: 12) {
                        Label(repository.stars.formatted(.number.notation(.compactName)), systemImage: "star.fill")
                            .foregroundStyle(AppTheme.amber)
                        if repository.forks > 0 {
                            Label(repository.forks.formatted(.number.notation(.compactName)), systemImage: "tuningfork")
                        }
                        if let language = repository.language { Label(language, systemImage: "chevron.left.forwardslash.chevron.right") }
                        if let updated = repository.updated { Text(updated.formatted(.relative(presentation: .named))) }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.muted)
                    .labelStyle(CompactLabelStyle())
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle").foregroundStyle(AppTheme.blue).accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Clones this repository into a new project")
        .accessibilityIdentifier("clone-repo-\(repository.fullName)")
    }

    private func clone(_ address: String, credential: GitCredential?, saveTyped: Bool, name: String? = nil) {
        working = name ?? (address as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
        failure = nil
        let typedUser = username.isEmpty ? "git" : username
        let typedToken = token
        Task {
            do {
                if saveTyped && !typedToken.isEmpty {
                    try GitCredentialVault.save(address: address, username: typedUser, token: typedToken)
                }
                let project = try await store.clone(address: address, credential: credential)
                dismiss()
                onCreated(project)
            } catch {
                failure = error.localizedDescription
            }
            working = nil
        }
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

/// Settings › GitHub account: one token, kept in the Keychain, used for search limits,
/// your repository list (private ones included), clone, pull and push on github.com.
struct GitHubAccountView: View {
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pythilo.githubLogin") private var githubLogin = ""
    @AppStorage("pythilo.gitName") private var gitName = ""
    @AppStorage("pythilo.gitEmail") private var gitEmail = ""
    @State private var token = ""
    @State private var checking = false
    @State private var failure: String?
    @State private var user: GitHubUser?
    @State private var confirmingSignOut = false

    private static let newToken = URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:user&description=Pythilo")!

    var body: some View {
        Form {
            if !githubLogin.isEmpty, GitHubClient.credential != nil {
                Section {
                    HStack(spacing: 12) {
                        AsyncImage(url: user?.avatarURL) { $0.resizable().scaledToFill() } placeholder: {
                            Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(AppTheme.raised)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user?.name ?? githubLogin).font(.system(size: 17, weight: .semibold))
                            Text("@\(githubLogin)").foregroundStyle(AppTheme.muted)
                            if let user, let open = user.publicRepos {
                                Text("\(open) public · \(user.privateRepos ?? 0) private repositories")
                                    .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("github-account-signed-in")
                } footer: {
                    Text("Clone shows your repositories, private ones included. Pull and push to github.com use this account.")
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmingSignOut = true }
                        .accessibilityIdentifier("github-sign-out")
                }
            } else {
                Section {
                    SecureField("Personal access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("github-token")
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Save account")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                    .accessibilityIdentifier("github-save")
                } header: {
                    Text("Token")
                } footer: {
                    Text("Create a token with the repo scope on GitHub, then paste it here. Pythilo checks it with GitHub and keeps it in the Keychain, on this device only.")
                }
                Section {
                    Link(destination: Self.newToken) { Label("Create a token on GitHub", systemImage: "arrow.up.right.square") }
                }
                if let failure { Text(failure).foregroundStyle(AppTheme.coralInk) }
            }
        }
        .navigationTitle("GitHub account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            if !githubLogin.isEmpty, let token = GitHubClient.token {
                user = try? await GitHubClient.user(token: token)
            }
        }
        .alert("Sign out of GitHub?", isPresented: $confirmingSignOut) {
            Button("Sign out", role: .destructive) {
                GitCredentialVault.remove(address: GitHubClient.host)
                githubLogin = ""
                user = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The token is removed from this device. Your projects stay.")
        }
    }

    private func signIn() async {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        failure = nil
        defer { checking = false }
        do {
            let found = try await GitHubClient.user(token: clean)
            try GitCredentialVault.save(address: GitHubClient.host, username: found.login, token: clean)
            user = found
            githubLogin = found.login
            token = ""
            if gitName.isEmpty, let name = found.name { gitName = name }
            if gitEmail.isEmpty, let email = found.email { gitEmail = email }
        } catch {
            failure = error.localizedDescription
        }
    }
}
