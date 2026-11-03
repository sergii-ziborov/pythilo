import SwiftUI
import UIKit

/// One project on screen. The arrangement comes from `WorkspaceLayout`; the
/// panels inside are the same everywhere.
struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    let onClose: () -> Void
    @State private var keyboard = KeyboardObserver()
    @State private var bridge = EditorKeyboardBridge()
    @State private var fold = FoldReading.none
    @State private var showingGit = false
    @State private var showingPackages = false
    @State private var showingRoom = false
    @State private var showingOpenFile = false
    @State private var sidebarVisible = true
    @State private var bottomPanelVisible = true
    @AppStorage("pythilo.drawerSide") private var drawerSideRaw = DrawerSide.left.rawValue
    @AppStorage("pythilo.drawerSwipe") private var drawerSwipe = true
    @AppStorage("pythilo.hideStatusBar") private var hideStatusBar = true

    private var drawerSide: DrawerSide { DrawerSide(rawValue: drawerSideRaw) ?? .left }
    private var session: RunSession { model.session }

    var body: some View {
        GeometryReader { geometry in
            let layout = resolvedLayout(geometry)
            let size = layoutSize(layout, geometry)
            ZStack {
                AppTheme.background.ignoresSafeArea()
                content(layout, size: size, safeArea: geometry.safeAreaInsets)
                    .ignoresSafeArea(.container)
                serverBanner(layout, safeArea: geometry.safeAreaInsets)
                    .animation(.snappy, value: model.previewURL)
                if usesDrawer(layout) { drawer(layout, size: size) }
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { HingeReader { fold = $0 } }
        }
        .ignoresSafeArea(.container)
        .statusBarHidden(hideStatusBar)
        .persistentSystemOverlays(hideStatusBar ? .hidden : .automatic)
        .defersSystemGestures(on: .bottom)
        .sheet(isPresented: $showingGit) { GitView(model: model) }
        .sheet(isPresented: $showingPackages) { PackagesView(model: model) }
        .sheet(isPresented: $showingRoom) { RoomSheet(model: model) }
        .sheet(isPresented: $showingOpenFile) { QuickOpenSheet(model: model) }
        .sheet(isPresented: $model.previewOpen) { PreviewSheet(model: model) }
        // Several chunks can land between two updates, so the recent tail is read,
        // not only the last chunk.
        .onChange(of: session.terminalRevision) { noticeOutput(session.terminalOutput, terminal: true) }
        .onChange(of: session.outputRevision) { noticeOutput(session.output, terminal: false) }
        .onChange(of: session.listening) { _, server in model.serverStarted(server) }
        #if DEBUG
        // For screenshots: -openSite YES opens the preview once the server listens.
        .onChange(of: model.previewURL) { _, url in
            if url != nil, UserDefaults.standard.bool(forKey: "openSite") { model.previewOpen = true }
        }
        // -migrateRestart YES taps Migrate & restart as soon as it appears.
        .onChange(of: model.unappliedMigrations) { _, count in
            if count > 0, UserDefaults.standard.bool(forKey: "migrateRestart"), !Self.tappedMigrate {
                Self.tappedMigrate = true
                model.migrateAndRestart()
            }
        }
        #endif
        .onChange(of: session.phase) { _, phase in
            if phase == .idle { model.clearPreview() }
            if phase == .paused { model.panel = .debug }
        }
        .onChange(of: model.selectedPath) { model.clearCompletions() }
        .background { shortcuts }
    }

    #if DEBUG
    private static var tappedMigrate = false
    #endif

    private func noticeOutput(_ chunks: [OutputChunk], terminal: Bool) {
        let tail = chunks.suffix(12).map(\.text).joined()
        model.updatePreview(from: tail)
        if terminal, session.isBusy, chunks.count > model.commandOutputStart {
            model.noticeMigrationWarning(in: chunks[model.commandOutputStart...].suffix(40).map(\.text).joined())
        }
        if !session.isBusy { model.noticeCommandList(in: tail) }
    }

    /// Over the code it sits above the dock, by the thumb; over a panel it moves
    /// to the top, so the terminal's keys stay free.
    @ViewBuilder
    private func serverBanner(_ layout: WorkspaceLayout, safeArea: EdgeInsets) -> some View {
        if let url = model.previewURL, !keyboard.isVisible, layout != .padLandscape {
            let atBottom = layout == .phone && model.panel == .code
            ServerBanner(
                url: url,
                framework: model.commands.framework?.rawValue,
                unappliedMigrations: model.unappliedMigrations,
                onOpen: { model.previewOpen = true },
                onMigrate: { model.migrateAndRestart() }
            )
            .frame(maxWidth: 520)
            .padding(.horizontal, 12)
            .padding(atBottom ? .bottom : .top, atBottom ? 62 : max(60, safeArea.top + 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: atBottom ? .bottom : .top)
            .transition(.move(edge: atBottom ? .bottom : .top).combined(with: .opacity))
        }
    }

    private func layoutSize(_ layout: WorkspaceLayout, _ geometry: GeometryProxy) -> CGSize {
        #if DEBUG
        if let size = Self.fakeSize { return size }
        #endif
        return geometry.size
    }

    #if DEBUG
    /// Device Hub cannot always drive the hinge, so debug launch arguments stand in
    /// for it on a larger simulator: -fakeLayout laptop -fakeSize 669x951.
    private static var fakeSize: CGSize? {
        let parts = (UserDefaults.standard.string(forKey: "fakeSize") ?? "").split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
    }
    #endif

    private func resolvedLayout(_ geometry: GeometryProxy) -> WorkspaceLayout {
        #if DEBUG
        let size = Self.fakeSize ?? geometry.size
        switch UserDefaults.standard.string(forKey: "fakeLayout") {
        case "laptop": return .duoLaptop(top: size.height / 2 - 12, hinge: 12)
        case "book": return .duoBook(left: size.width / 2 - 6, hinge: 12)
        case "cover": return .cover
        case "flat": return .duoFlat
        case "padland": return .padLandscape
        default: break
        }
        #endif
        return WorkspaceLayout.resolve(size: geometry.size, container: geometry.frame(in: .global), fold: fold)
    }

    private func usesDrawer(_ layout: WorkspaceLayout) -> Bool {
        switch layout {
        case .phone, .phoneLandscape, .cover, .duoLaptop: true
        default: false
        }
    }

    private var shortcuts: some View {
        ZStack {
            Button("") { sidebarVisible.toggle(); model.drawerOpen.toggle() }.keyboardShortcut("b", modifiers: .command)
            Button("") { bottomPanelVisible.toggle() }.keyboardShortcut("j", modifiers: .command)
            Button("") { showingOpenFile = true }.keyboardShortcut("p", modifiers: .command)
            Button("") { model.saveAll() }.keyboardShortcut("s", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func drawer(_ layout: WorkspaceLayout, size: CGSize) -> some View {
        FileDrawerOverlay(
            isOpen: $model.drawerOpen,
            side: drawerSide,
            swipeEnabled: drawerSwipe && !keyboard.isVisible,
            width: min(328, size.width - 56)
        ) {
            VStack(spacing: 0) {
                HStack {
                    if drawerSide == .right { Spacer() }
                    RoundIconButton(
                        systemImage: drawerSide == .left ? "chevron.left" : "chevron.right",
                        label: "Close files"
                    ) { model.drawerOpen = false }
                    if drawerSide == .left { Spacer() }
                }
                .padding(.horizontal, 12)
                .padding(.top, layout == .phone ? 8 : 10)
                ProjectColumn(
                    model: model,
                    onOpen: { model.drawerOpen = false },
                    onGit: {
                        model.drawerOpen = false
                        showingGit = true
                    },
                    onPackages: {
                        model.drawerOpen = false
                        showingPackages = true
                    },
                    onShareRoom: {
                        model.drawerOpen = false
                        showingRoom = true
                    },
                    onPreview: {
                        model.drawerOpen = false
                        model.previewOpen = true
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ layout: WorkspaceLayout, size: CGSize, safeArea: EdgeInsets) -> some View {
        switch layout {
        case .phone: phone
        case .phoneLandscape: phoneLandscape(size: size)
        case let .duoLaptop(top, hinge): duoLaptop(top: top, hinge: hinge)
        case let .duoBook(left, hinge): duoBook(left: left, hinge: hinge)
        case .duoFlat: duoFlat
        case .cover: cover
        case .padLandscape: pad(bottomHeight: 230, showsPreviewColumn: true)
        case .padPortrait: pad(bottomHeight: 310, showsPreviewColumn: false)
        }
    }

    // MARK: Pieces

    private var backButton: some View {
        RoundIconButton(systemImage: "chevron.left", label: "Back to projects") {
            model.saveAll()
            onClose()
        }
        .accessibilityIdentifier("workspace-back")
    }

    private var filesButton: some View {
        RoundIconButton(systemImage: "folder", label: "Open project files", tint: AppTheme.selectionInk, fill: AppTheme.selection) {
            model.drawerOpen.toggle()
        }
        .accessibilityIdentifier("files-button")
    }

    /// Packages, the web preview, Git and sharing, each with its name, behind one button.
    private var actionsButton: some View {
        WorkspaceProjectMenu(
            model: model,
            onGit: { showingGit = true },
            onPackages: { showingPackages = true },
            onShareRoom: { showingRoom = true },
            round: true
        )
    }

    @ViewBuilder
    private var previewButton: some View {
        if model.previewURL != nil {
            RoundIconButton(systemImage: "globe", label: "Open web preview", tint: AppTheme.selectionInk, fill: AppTheme.selection) {
                model.previewOpen = true
            }
            .accessibilityIdentifier("preview-button")
        }
    }

    private var menu: some View {
        WorkspaceProjectMenu(
            model: model,
            onGit: { showingGit = true },
            onPackages: { showingPackages = true },
            onShareRoom: { showingRoom = true }
        )
    }

    private var hideKeyboardButton: some View {
        RoundIconButton(systemImage: "keyboard.chevron.compact.down", label: "Hide keyboard") {
            bridge.dismissKeyboard()
        }
    }

    private var hairline: some View { Rectangle().fill(AppTheme.border).frame(height: 1) }

    private func dock(_ height: CGFloat = 50) -> some View {
        PanelDockBar(model: model)
            .frame(height: height)
            .background(.ultraThinMaterial, ignoresSafeAreaEdges: [])
            .overlay(alignment: .top) { hairline }
    }

    // MARK: iPhone, vertical

    /// Buttons sit beside the camera, so the top of the screen is working space.
    /// Code runs to the bottom edge, under the dock.
    private var phone: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 54)
                if model.panel == .code {
                    HStack(spacing: 0) {
                        FileTabsBar(model: model)
                        menu
                    }
                    .frame(height: 42)
                    .background(AppTheme.rail, ignoresSafeAreaEdges: [])
                    hairline
                    EditorPane(model: model, bridge: bridge, bottomClearance: keyboard.isVisible ? 0 : 50)
                } else {
                    hairline
                    ActivePanel(model: model)
                        .padding(.bottom, keyboard.isVisible ? 0 : 50)
                }
            }
            HStack {
                HStack(spacing: 4) {
                    backButton
                    if drawerSide == .left { filesButton }
                }
                Spacer()
                HStack(spacing: 4) {
                    if drawerSide == .right { filesButton }
                    RunControl(model: model)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            if !keyboard.isVisible {
                VStack {
                    Spacer()
                    dock()
                }
                .ignoresSafeArea(.keyboard)
            }
        }
    }

    // MARK: iPhone, horizontal

    /// A rail on the camera's side, split around the camera. Output moves beside
    /// the code while something runs, because the screen is wide and short.
    private func phoneLandscape(size: CGSize) -> some View {
        let onLeading = cameraIsOnLeading()
        let showsSideOutput = session.isBusy && model.panel != .terminal && model.panel != .debug && model.panel != .problems
        return HStack(spacing: 0) {
            if onLeading { landscapeRail(height: size.height) }
            VStack(spacing: 0) {
                if !keyboard.isVisible, !showsSideOutput, model.panel == .code {
                    HStack(spacing: 0) {
                        FileTabsBar(model: model)
                        menu
                    }
                    .frame(height: 36)
                    .background(AppTheme.rail, ignoresSafeAreaEdges: [])
                    hairline
                }
                ZStack(alignment: .bottomTrailing) {
                    if model.panel == .code || showsSideOutput {
                        HStack(spacing: 0) {
                            EditorPane(model: model, bridge: bridge)
                            if showsSideOutput {
                                Rectangle().fill(AppTheme.border).frame(width: 1)
                                OutputPanel(model: model, showsStrip: true, fontSize: 13)
                                    .frame(width: min(364, size.width * 0.44))
                                    .background(AppTheme.panel, ignoresSafeAreaEdges: [])
                            }
                        }
                    } else {
                        ActivePanel(model: model)
                    }
                    if !keyboard.isVisible {
                        HStack(spacing: 6) {
                            RunControl(model: model, height: 48)
                        }
                        .padding(.trailing, onLeading ? 14 : 8)
                        .padding(.bottom, 14)
                        .opacity(showsSideOutput ? 0 : 1)
                    }
                }
            }
            if !onLeading { landscapeRail(height: size.height) }
        }
        .overlay(alignment: onLeading ? .topTrailing : .topLeading) {
            if showsSideOutput {
                RunControl(model: model, height: 44).padding(.top, 2).padding(.horizontal, 8).opacity(0.001).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func landscapeRail(height: CGFloat) -> some View {
        VStack(spacing: 6) {
            if keyboard.isVisible {
                hideKeyboardButton
                RunControl(model: model, iconOnly: true)
                Spacer(minLength: 0)
            } else {
                backButton
                filesButton
                // The camera sits in the middle of this edge.
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    HStack(spacing: 0) {
                        railPanel(.code)
                        railPanel(.problems)
                    }
                    HStack(spacing: 0) {
                        railPanel(.output)
                        railPanel(.terminal)
                    }
                    railPanel(.debug)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 62)
        .frame(maxHeight: .infinity)
        .background(AppTheme.rail, ignoresSafeAreaEdges: [])
        .overlay(alignment: cameraIsOnLeading() ? .trailing : .leading) {
            Rectangle().fill(AppTheme.border).frame(width: 1)
        }
    }

    private func railPanel(_ panel: WorkspacePanel) -> some View {
        Button {
            model.panel = panel
        } label: {
            Image(systemName: panel.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.panel == panel ? AppTheme.blue : AppTheme.muted)
                .frame(width: 30, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(panel.title)
    }

    // MARK: iPhone Duo

    private func duoHeader(cameraClearance: CGFloat = 116) -> some View {
        HStack(spacing: 6) {
            backButton
            filesButton
            FileTabsBar(model: model).frame(height: 44)
            actionsButton
            previewButton
            RunControl(model: model)
        }
        .padding(.leading, 12)
        .padding(.trailing, cameraClearance)
        .frame(height: 60)
    }

    /// Code on the upper half. The hinge stays empty. The lower half holds the
    /// dock and either a panel or the keyboard.
    private func duoLaptop(top: CGFloat, hinge: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                duoHeader()
                hairline
                EditorPane(model: model, bridge: bridge)
            }
            .frame(height: top)
            .clipped()
            Color.black.frame(height: hinge).accessibilityHidden(true)
            HStack(spacing: 0) {
                PanelDockBar(model: model, panels: [.problems, .output, .terminal, .debug])
                if keyboard.isVisible {
                    Button {
                        bridge.dismissKeyboard()
                    } label: {
                        Label("Hide", systemImage: "keyboard.chevron.compact.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.blue)
                            .frame(width: 92, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 50)
            hairline
            ActivePanel(model: model, fallback: .output)
                .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Two pages: the project on the left, the code on the right of the hinge.
    private func duoBook(left: CGFloat, hinge: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ProjectColumn(
                    model: model,
                    compact: true,
                    rowHeight: 36,
                    showsSearch: false,
                    showsFooter: false,
                    leading: AnyView(backButton),
                    onGit: { showingGit = true },
                    onPackages: { showingPackages = true }
                )
                .frame(maxHeight: .infinity)
                hairline
                PanelDockBar(model: model, panels: [.problems, .output, .terminal, .debug]).frame(height: 48)
                hairline
                ActivePanel(model: model, fallback: .terminal).frame(maxHeight: .infinity).background(AppTheme.panel, ignoresSafeAreaEdges: [])
            }
            .frame(width: left)
            .background(AppTheme.rail, ignoresSafeAreaEdges: [])
            Color.black.frame(width: hinge).accessibilityHidden(true)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    FileTabsBar(model: model).frame(height: 44)
                    actionsButton
                    previewButton
                    RunControl(model: model)
                }
                .padding(.leading, 4)
                .padding(.trailing, 122)
                .frame(height: 60)
                hairline
                EditorPane(model: model, bridge: bridge)
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Open flat, with no hinge in play: a tree, code above, a panel below.
    private var duoFlat: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack { backButton; Spacer() }.padding(.leading, 8).padding(.top, 8)
                ProjectColumn(
                    model: model,
                    compact: true,
                    rowHeight: 38,
                    showsSearch: false,
                    onGit: { showingGit = true },
                    onPackages: { showingPackages = true }
                )
            }
            .frame(width: 216)
            .background(AppTheme.rail, ignoresSafeAreaEdges: [])
            Rectangle().fill(AppTheme.border).frame(width: 1)
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    FileTabsBar(model: model).frame(height: 44)
                    actionsButton
                    previewButton
                    RunControl(model: model)
                }
                .padding(.trailing, 116)
                .frame(height: 60)
                hairline
                EditorPane(model: model, bridge: bridge)
                if !keyboard.isVisible {
                    hairline
                    PanelDockBar(model: model, panels: [.problems, .output, .terminal, .debug]).frame(height: 50)
                    hairline
                    ActivePanel(model: model).frame(height: 240).background(AppTheme.panel, ignoresSafeAreaEdges: [])
                }
            }
        }
    }

    // MARK: Duo folded

    /// The cover screen is short, so a side rail keeps the height. While typing
    /// the rail goes away and the keyboard gets the room.
    private var cover: some View {
        Group {
            if keyboard.isVisible {
                VStack(spacing: 0) {
                    HStack {
                        filesButton
                        Text((model.selectedPath as NSString?)?.lastPathComponent ?? "")
                            .font(.system(size: 12.5, design: .monospaced))
                            .lineLimit(1)
                            .frame(maxWidth: 118, alignment: .leading)
                        Spacer()
                        RunControl(model: model, iconOnly: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    hairline.padding(.top, 2)
                    if model.panel == .code {
                        EditorPane(model: model, bridge: bridge)
                    } else {
                        ActivePanel(model: model)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 6) {
                        backButton
                        filesButton
                        Spacer(minLength: 8)
                        PanelDockBar(model: model, vertical: true, showsLabels: false).frame(height: 280)
                    }
                    .padding(.vertical, 8)
                    .frame(width: 58)
                    .background(AppTheme.rail, ignoresSafeAreaEdges: [])
                    Rectangle().fill(AppTheme.border).frame(width: 1)
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 40)
                        HStack(spacing: 4) {
                            FileTabsBar(model: model)
                            actionsButton
                            previewButton
                            RunControl(model: model)
                        }
                        .frame(height: 44)
                        .padding(.trailing, 10)
                        hairline
                        if model.panel == .code {
                            EditorPane(model: model, bridge: bridge)
                        } else {
                            ActivePanel(model: model)
                        }
                    }
                }
            }
        }
    }

    // MARK: iPad

    /// Tree, code and panels stay on screen together. With a hardware keyboard
    /// the tree can collapse to a rail, and the symbol keys to a row of shortcuts.
    private func pad(bottomHeight: CGFloat, showsPreviewColumn: Bool) -> some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                VStack(spacing: 0) {
                    ProjectColumn(
                        model: model,
                        compact: true,
                        rowHeight: 34,
                        leading: AnyView(backButton),
                        onGit: { showingGit = true },
                        onPackages: { showingPackages = true }
                    )
                    .padding(.top, 8)
                }
                .frame(width: showsPreviewColumn ? 272 : 240)
                .background(AppTheme.rail, ignoresSafeAreaEdges: [])
                Rectangle().fill(AppTheme.border).frame(width: 1)
            } else {
                VStack(spacing: 4) {
                    RoundIconButton(systemImage: "sidebar.left", label: "Show files", tint: AppTheme.selectionInk, fill: AppTheme.selection) {
                        sidebarVisible = true
                    }
                    PanelDockBar(model: model, vertical: true, showsLabels: false, panels: [.problems, .output, .terminal, .debug]).frame(height: 220)
                    Spacer()
                }
                .padding(.vertical, 10)
                .frame(width: 52)
                .background(AppTheme.rail, ignoresSafeAreaEdges: [])
                Rectangle().fill(AppTheme.border).frame(width: 1)
            }
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    FileTabsBar(model: model, fullPathForSelected: true)
                    menu
                    RunControl(model: model, height: 40).padding(.trailing, 8)
                }
                .frame(height: 50)
                .background(AppTheme.rail, ignoresSafeAreaEdges: [])
                hairline
                EditorPane(model: model, bridge: bridge)
                    .overlay(alignment: .bottomTrailing) {
                        if keyboard.hasHardwareKeyboard {
                            ShortcutPill { bridge.focusEditor() }
                                .padding(14)
                                .accessibilityIdentifier("shortcut-pill")
                        }
                    }
                if bottomPanelVisible {
                    hairline
                    VStack(spacing: 0) {
                        padPanelTabs
                        hairline
                        ActivePanel(model: model)
                    }
                    .frame(height: bottomHeight)
                    .background(AppTheme.panel, ignoresSafeAreaEdges: [])
                }
            }
            if showsPreviewColumn, let url = model.previewURL {
                Rectangle().fill(AppTheme.border).frame(width: 1)
                PreviewColumn(url: url).frame(width: 340)
            }
        }
        .padding(.top, 20)
    }

    private var padPanelTabs: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
            ForEach([WorkspacePanel.problems, .output, .terminal, .debug]) { panel in
                let active = model.panel == panel
                Button {
                    model.panel = panel
                } label: {
                    HStack(spacing: 5) {
                        Text(panel.title)
                        if panel == .problems, !model.problems.isEmpty {
                            Text("\(model.problems.count)").foregroundStyle(AppTheme.amber)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(active ? AppTheme.blue : AppTheme.muted)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .overlay(alignment: .bottom) {
                        if active { Rectangle().fill(AppTheme.blue).frame(height: 2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("panel-\(panel.rawValue)")
            }
            }
            }
            if model.previewURL != nil { previewButton.scaleEffect(0.82) }
            Button {
                bottomPanelVisible = false
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(AppTheme.muted).frame(width: 44, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide panel")
        }
    }
}

struct QuickOpenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel

    var body: some View {
        NavigationStack {
            ScrollView {
                FileTreeView(model: model, onOpen: { dismiss() }).padding(10)
            }
            .navigationTitle("Open a file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
