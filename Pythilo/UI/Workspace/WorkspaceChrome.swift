import SwiftUI
import UIKit

/// Run becomes Stop while Python works, and only reports what Python has done.
struct RunControl: View {
    @Bindable var model: WorkspaceModel
    var iconOnly = false
    var height: CGFloat = 44
    private var session: RunSession { model.session }

    var body: some View {
        Group {
            switch session.phase {
            case .idle, .starting:
                Button(action: model.runSelected) {
                    runLabel
                }
                .contextMenu {
                    Button("Debug", systemImage: "ladybug") { model.debugSelected() }
                    Button("Run tests", systemImage: "checkmark.circle") {
                        model.panel = .terminal
                        model.runTerminal("pytest -q")
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Run")
                .accessibilityIdentifier("run-button")
            case .running, .waitingForInput, .paused:
                Button(action: session.stop) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(AppTheme.coral).frame(width: 12, height: 12)
                        if !iconOnly { Text("Stop") }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.coralInk)
                    .padding(.horizontal, iconOnly ? 0 : 15)
                    .frame(minWidth: height, minHeight: height)
                    .background(AppTheme.coralFill, in: Capsule())
                    .overlay { Capsule().stroke(AppTheme.coral, lineWidth: 1) }
                }
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("stop-button")
            case .cancelling, .unresponsive:
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    if !iconOnly { Text("Stopping") }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.secondary)
                .padding(.horizontal, iconOnly ? 0 : 13)
                .frame(minWidth: height, minHeight: height)
                .background(AppTheme.raised, in: Capsule())
                .accessibilityIdentifier("stopping")
            }
        }
        .buttonStyle(.app)
        .fixedSize()
    }

    private var runLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: "play.fill").font(.system(size: iconOnly ? 17 : 14))
            if !iconOnly { Text("Run") }
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(AppTheme.onRun)
        .padding(.leading, iconOnly ? 0 : 13)
        .padding(.trailing, iconOnly ? 0 : 16)
        .frame(minWidth: height, minHeight: height)
        .background(AppTheme.run, in: Capsule())
    }
}

/// Five panels, horizontally at the screen's bottom or vertically in a rail.
struct PanelDockBar: View {
    @Bindable var model: WorkspaceModel
    var vertical = false
    var showsLabels = true
    var panels: [WorkspacePanel] = WorkspacePanel.allCases

    private func item(_ panel: WorkspacePanel) -> some View {
        let active = model.panel == panel
        let count = panel == .problems ? model.problems.count : 0
        return Button {
            model.panel = panel
        } label: {
            VStack(spacing: 2) {
                Image(systemName: panel.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 21)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(AppTheme.onRun)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 15, minHeight: 15)
                                .background(Color(uiColor: UIColor(hex: 0xF2C25A)), in: Capsule())
                                .offset(x: 11, y: -5)
                        }
                    }
                if showsLabels {
                    Text(panel.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(active ? AppTheme.blue : AppTheme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.app)
        .accessibilityLabel(panel.title)
        .accessibilityIdentifier("panel-\(panel.rawValue)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    var body: some View {
        if vertical {
            VStack(spacing: 2) { ForEach(panels) { item($0) } }
        } else {
            HStack(spacing: 0) { ForEach(panels) { item($0) } }
                .padding(.horizontal, 12)
        }
    }
}

struct FileTabsBar: View {
    @Bindable var model: WorkspaceModel
    var fullPathForSelected = false
    @State private var showingActions = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.tabs, id: \.self) { path in
                    let selected = model.selectedPath == path
                    Button {
                        model.open(path)
                    } label: {
                        HStack(spacing: 6) {
                            FileIconView(name: (path as NSString).lastPathComponent)
                            Text(fullPathForSelected && selected ? path : (path as NSString).lastPathComponent)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .regular, design: .monospaced))
                                .lineLimit(1)
                            if model.isUnsaved(path) {
                                Circle().fill(AppTheme.primary).frame(width: 7, height: 7).accessibilityLabel("Unsaved")
                            }
                        }
                        .foregroundStyle(selected ? AppTheme.primary : AppTheme.muted)
                        .padding(.leading, 7)
                        .padding(.trailing, 10)
                        .frame(maxHeight: .infinity)
                        .background(selected ? AppTheme.editor : Color.clear, ignoresSafeAreaEdges: [])
                        .overlay(alignment: .top) {
                            if selected { Rectangle().fill(AppTheme.run).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.app)
                    .contextMenu {
                        Button("Close tab", systemImage: "xmark") { model.close(path) }
                    }
                    .accessibilityIdentifier("tab-\(path)")
                }
            }
        }
    }
}

/// Presents the system share sheet, or an alert, over whatever is on screen.
@MainActor
func presentOverTopScreen(_ controller: UIViewController) {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    if let popover = controller.popoverPresentationController, let view = top?.view {
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 1, height: 1)
    }
    top?.present(controller, animated: true)
}

struct WorkspaceProjectMenu: View {
    @Bindable var model: WorkspaceModel
    let onGit: () -> Void
    let onPackages: () -> Void
    let onShareRoom: () -> Void
    /// A round header button rather than the plain one at the end of the tabs.
    var round = false

    var body: some View {
        Menu {
            Button("Packages", systemImage: "shippingbox", action: onPackages)
            if model.previewURL != nil {
                Button("Web preview", systemImage: "globe") { model.previewOpen = true }
            }
            Button("Git", systemImage: "arrow.triangle.branch", action: onGit)
            Button("Share with an AI client or person", systemImage: "person.2", action: onShareRoom)
            Button("Share as a link", systemImage: "link") { shareSnapshotLink() }
                .accessibilityIdentifier("share-snapshot-link")
            Divider()
            Button("Debug", systemImage: "ladybug") {
                model.panel = .debug
            }
            Button("Run tests", systemImage: "checkmark.circle") {
                model.panel = .terminal
                model.runTerminal("pytest -q")
            }
            if let selected = model.selectedPath {
                Divider()
                Button("Close \((selected as NSString).lastPathComponent)", systemImage: "xmark") { model.close(selected) }
            }
        } label: {
            if round {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.raised, in: Circle())
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityLabel("Project actions")
        .accessibilityIdentifier("project-menu")
    }

    /// The project's text files, packed into a link that opens them in the
    /// website's Playground or in Pythilo. No server keeps a copy.
    private func shareSnapshotLink() {
        model.saveAll()
        do {
            let snapshot = try ShareSnapshot.of(project: model.project.url, main: model.selectedPath)
            let link = try snapshot.webLink()
            let note = "\(snapshot.files.count) file\(snapshot.files.count == 1 ? "" : "s") from \(snapshot.name), in a Pythilo link"
            _ = note
            presentOverTopScreen(UIActivityViewController(activityItems: [link], applicationActivities: nil))
        } catch {
            let alert = UIAlertController(title: "Cannot make a link", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            presentOverTopScreen(alert)
        }
    }
}

/// The editor for whatever the selected tab holds.
struct EditorPane: View {
    @Bindable var model: WorkspaceModel
    let bridge: EditorKeyboardBridge
    var bottomClearance: CGFloat = 0
    var leadingClearance: CGFloat = 0

    var body: some View {
        Group {
            if let path = model.selectedPath {
                if model.isNotebook(path) {
                    NotebookView(model: model, path: path)
                } else if model.isDatabase(path) {
                    DatabaseView(model: model, path: path)
                        .id(path)
                } else if model.isText(path) {
                    editor(path)
                } else {
                    binary(path)
                }
            } else {
                ContentUnavailableView("No file open", systemImage: "doc", description: Text("Open the files and pick one, or swipe from the edge."))
            }
        }
        .background(AppTheme.editor, ignoresSafeAreaEdges: [])
        .overlay(alignment: .bottomTrailing) { completionList }
    }

    private func editor(_ path: String) -> some View {
        let room = PlaygroundRooms.shared.room(for: model.project)
        let shared = room?.session.document?.files[path] != nil
        return SyntaxCodeEditor(
            text: Binding(get: { model.text(path) }, set: { model.setText($0, for: path); model.requestCompletions() }),
            cursorOffset: $model.cursorOffset,
            filePath: path,
            isEditable: !(shared && room?.session.link.isReadOnly == true),
            remoteSelections: shared ? room?.session.selections ?? [] : [],
            collaborationSelection: shared ? room?.session.localSelection : nil,
            onSelectionChange: { range in if shared { room?.select(path: path, range: range) } },
            breakpoints: model.breakpoints[path] ?? [],
            debugLine: debugLine(path),
            onBreakpoint: { line in
                var lines = model.breakpoints[path] ?? []
                if lines.contains(line) { lines.remove(line) } else { lines.insert(line) }
                model.breakpoints[path] = lines
            },
            tracksTyping: false,
            diagnostics: model.diagnostics(for: path),
            navigationTarget: model.navigation?.filePath == path ? model.navigation : nil,
            keyboardBridge: bridge,
            onRequestCompletion: { model.requestCompletions() }
        )
        .id(path)
        .environment(\.codeEditorChrome, CodeEditorChrome(bottom: bottomClearance, leading: leadingClearance))
    }

    private func debugLine(_ path: String) -> Int? {
        guard let pause = model.session.debugPause else { return nil }
        return pause.file.hasSuffix("/" + path) ? pause.line : nil
    }

    private func binary(_ path: String) -> some View {
        VStack(spacing: 10) {
            FileIconView(name: (path as NSString).lastPathComponent)
            Text((path as NSString).lastPathComponent).font(.system(size: 16, weight: .semibold, design: .monospaced))
            Text("This file is not text, so it does not open in the editor.")
                .font(.system(size: 14)).foregroundStyle(AppTheme.muted)
            ShareLink(item: model.fileURL(path)) { Label("Share file", systemImage: "square.and.arrow.up") }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var completionList: some View {
        if !model.completions.isEmpty {
            VStack(spacing: 0) {
                ForEach(model.completions.prefix(4)) { item in
                    Button {
                        model.acceptCompletion(item)
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.kind == "function" ? "ƒ" : item.kind == "class" ? "C" : item.kind == "module" ? "m" : "v")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.violet)
                                .frame(width: 14)
                            Text(item.label).font(.system(size: 13.5, design: .monospaced)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(item.kind).font(.system(size: 11)).foregroundStyle(AppTheme.muted)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.app)
                }
            }
            .frame(width: 240)
            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .padding(10)
            .padding(.bottom, bottomClearance)
            .accessibilityIdentifier("completions")
        }
    }
}

/// Whichever panel is active, for layouts that show a panel on its own.
struct ActivePanel: View {
    @Bindable var model: WorkspaceModel
    var fallback: WorkspacePanel = .output

    var body: some View {
        switch model.panel == .code ? fallback : model.panel {
        case .problems: ProblemsPanel(model: model)
        case .terminal: TerminalPanel(model: model)
        case .debug: DebugPanel(model: model)
        default: OutputPanel(model: model)
        }
    }
}

/// The floating row of shortcuts an iPad shows once a hardware keyboard is
/// attached, in place of the on-screen symbol keys.
struct ShortcutPill: View {
    let onShowKeys: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pill(["⌘R Run", "⌘. Stop", "⌘B Files", "⌘J Panel", "⌘P Open"])
            pill(["⌘R Run", "⌘. Stop"])
            pill([])
        }
    }

    private func pill(_ items: [String]) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                Text(item).lineLimit(1).fixedSize().padding(.horizontal, 7)
            }
            Button(action: onShowKeys) {
                Image(systemName: "keyboard")
                    .frame(width: 40, height: 36)
                    .background(AppTheme.border, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.app)
            .accessibilityLabel("Show on-screen keys")
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(AppTheme.secondary)
        .padding(.horizontal, 4)
        .frame(height: 44)
        .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 13, y: 6)
    }
}

/// Room the editor leaves around its code for controls floating over it.
struct CodeEditorChrome: Equatable {
    var bottom: CGFloat = 0
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}

private struct CodeEditorChromeKey: EnvironmentKey {
    static let defaultValue = CodeEditorChrome()
}

extension EnvironmentValues {
    var codeEditorChrome: CodeEditorChrome {
        get { self[CodeEditorChromeKey.self] }
        set { self[CodeEditorChromeKey.self] = newValue }
    }
}
