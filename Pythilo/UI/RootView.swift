import SwiftUI

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
        .task { _ = RunSession.shared }
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
            PlaygroundView(store: store, onOpen: open)
        }
    }

    private func open(_ project: Project) {
        workspace = WorkspaceModel(project: project)
    }
}

extension WorkspaceModel: Identifiable {
    nonisolated var id: String { project.id }
}
