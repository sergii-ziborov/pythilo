import SwiftUI
import UIKit

enum AppSection: String, CaseIterable, Identifiable {
    case projects, learn, labs, playground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        case .learn: "Learn"
        case .labs: "Labs"
        case .playground: "Playground"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: "folder"
        case .learn: "book"
        case .labs: "testtube.2"
        case .playground: "person.2"
        }
    }
}

struct RootView: View {
    @State private var section: AppSection = .projects
    @State private var store = ProjectStore.shared
    @State private var workspace: WorkspaceModel?
    @State private var showingSettings = false
    @State private var incomingRoomLink: String?
    @State private var linkFailure: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $section) {
            ForEach(AppSection.allCases) { section in
                sectionView(section)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(section)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .fullScreenCover(item: $workspace) { model in
            WorkspaceView(model: model) { workspace = nil }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .alert("Cannot open this link", isPresented: Binding(get: { linkFailure != nil }, set: { if !$0 { linkFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkFailure ?? "")
        }
        .onOpenURL { url in
            // A link with the files in it opens them as a new project.
            do {
                if let snapshot = try ShareSnapshot.from(url: url) {
                    workspace?.saveAll()
                    workspace = nil
                    let project = try snapshot.createProject(in: store)
                    section = .projects
                    open(project)
                    return
                }
            } catch {
                linkFailure = error.localizedDescription
                return
            }
            guard url.scheme?.lowercased() == "pythilo" else { return }
            incomingRoomLink = url.absoluteString
            workspace?.saveAll()
            workspace = nil
            section = .playground
        }
        .onChange(of: scenePhase) { _, phase in
            PlaygroundRooms.shared.setForeground(phase == .active)
        }
        .task {
            _ = RunSession.shared
            #if DEBUG
            openFromLaunchArguments()
            #endif
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .projects:
            ProjectsView(store: store, onOpen: open, onSettings: { showingSettings = true })
        case .learn:
            LearnView(onOpenProject: open)
        case .labs:
            LabsView()
        case .playground:
            PlaygroundView(store: store, onOpen: open, incomingLink: $incomingRoomLink)
        }
    }

    private func open(_ project: Project) {
        workspace = WorkspaceModel(project: project)
    }

    #if DEBUG
    /// For screenshots: -openTemplate django -panel terminal -drawer YES.
    private func openFromLaunchArguments() {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "tab").flatMap(AppSection.init(rawValue:)) { section = tab }
        if let link = defaults.string(forKey: "roomLink") {
            incomingRoomLink = link
            section = .playground
        }
        if let name = defaults.string(forKey: "openProject"), let project = store.projects.first(where: { $0.name == name }) {
            workspace = WorkspaceModel(project: project)
            return
        }
        guard let id = defaults.string(forKey: "openTemplate"),
              let template = ProjectTemplate.all.first(where: { $0.id == id }) else { return }
        let existing = store.projects.first { $0.name == "shot-\(id)" }
        guard let project = existing ?? (try? store.create(name: "shot-\(id)", template: template)) else { return }
        let model = WorkspaceModel(project: project)
        if let panel = defaults.string(forKey: "panel").flatMap(WorkspacePanel.init(rawValue:)) { model.panel = panel }
        for path in (defaults.string(forKey: "expand") ?? "").split(separator: ",") { model.expanded.insert(String(path)) }
        if let file = defaults.string(forKey: "openFile") { model.open(file); model.panel = defaults.string(forKey: "panel").flatMap(WorkspacePanel.init(rawValue:)) ?? .code }
        model.drawerOpen = defaults.bool(forKey: "drawer")
        if let line = defaults.string(forKey: "terminal") { model.panel = .terminal; model.runTerminal(line) }
        workspace = model
        if defaults.bool(forKey: "startMCP") {
            let host = MCPHost.shared
            host.start(project: project)
            host.workspace = model
            for (permission, grant) in [(MCPPermission.run, MCPGrant.allow), (.commit, .allow)] { host.grants[permission] = grant }
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "mcp-token")
            try? host.token.write(to: file, atomically: true, encoding: .utf8)
        }
        if defaults.string(forKey: "orientation") == "landscape",
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
        }
    }
    #endif
}

extension WorkspaceModel: Identifiable {
    nonisolated var id: String { project.id }
}
