import SwiftUI

enum DrawerSide: String, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }
    var title: String { self == .left ? "Left" : "Right" }
}

/// The project column: name, Git state, search, new items and the tree. It is
/// the drawer on a phone and a permanent column where there is room.
struct ProjectColumn: View {
    @Bindable var model: WorkspaceModel
    var compact = false
    var rowHeight: CGFloat = 40
    var showsSearch = true
    var showsFooter = true
    var onOpen: () -> Void = {}
    var leading: AnyView?
    var onGit: () -> Void = {}
    var onPackages: () -> Void = {}
    var onShareRoom: (() -> Void)?
    var onPreview: (() -> Void)?
    @State private var search = ""
    @State private var creating: NewItemKind?

    private enum NewItemKind: String, Identifiable {
        case file, folder
        var id: String { rawValue }
    }

    private var changeCount: Int { model.gitSnapshot?.changes.count ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let leading { leading }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.project.name)
                        .font(.system(size: compact ? 16 : 20, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let snapshot = model.gitSnapshot {
                            Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .semibold))
                            Text(snapshot.branch)
                            if changeCount > 0 {
                                Text("· \(changeCount) changes").foregroundStyle(AppTheme.amber)
                            }
                        } else {
                            Text("No Git repository")
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                }
                Spacer(minLength: 2)
                newButton("doc.badge.plus", "New file", AppTheme.mint) { creating = .file }
                newButton("folder.badge.plus", "New folder", AppTheme.blue) { creating = .folder }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                    TextField("Find a file", text: $search)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            ScrollView {
                FileTreeView(model: model, rowHeight: rowHeight, filter: search, onOpen: onOpen)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
            }

            if showsFooter {
                Rectangle().fill(AppTheme.border).frame(height: 1)
                HStack(spacing: 0) {
                    footerButton("shippingbox", "Packages", AppTheme.amber, action: onPackages)
                    footerButton("arrow.triangle.branch", "Git", AppTheme.coral, action: onGit)
                    if let onShareRoom {
                        footerButton("person.2", "Room", AppTheme.mint, action: onShareRoom)
                    }
                    if let onPreview, model.previewURL != nil {
                        footerButton("globe", "Site", AppTheme.blue, action: onPreview)
                    }
                    ShareLink(item: model.project.url) {
                        footerLabel("square.and.arrow.up", "Share", AppTheme.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .sheet(item: $creating) { kind in
            NewItemSheet(model: model, target: NewItemTarget(folder: nil), startsAsFolder: kind == .folder)
        }
    }

    private func newButton(_ symbol: String, _ label: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: compact ? 36 : 44, height: 44)
                .background(compact ? Color.clear : AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func footerButton(_ symbol: String, _ title: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { footerLabel(symbol, title, tint) }.buttonStyle(.plain)
    }

    private func footerLabel(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(tint)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// Slides over the workspace from the chosen edge. Opens by button or by a swipe
/// from that edge, and closes by a swipe back or a tap outside.
struct FileDrawerOverlay<Content: View>: View {
    @Binding var isOpen: Bool
    let side: DrawerSide
    let swipeEnabled: Bool
    var width: CGFloat = 328
    @ViewBuilder let content: () -> Content
    @State private var drag: CGFloat = 0

    private var direction: CGFloat { side == .left ? 1 : -1 }

    /// How far the drawer has come out, from 0 to its width.
    private var reveal: CGFloat {
        let base = isOpen ? width : 0
        return min(width, max(0, base + drag * direction))
    }

    var body: some View {
        ZStack(alignment: side == .left ? .leading : .trailing) {
            Color.black.opacity(0.45 * Double(reveal / width))
                .ignoresSafeArea()
                .allowsHitTesting(isOpen)
                .onTapGesture { close() }
                .accessibilityHidden(!isOpen)

            if swipeEnabled, !isOpen {
                Color.clear
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(openGesture)
                    .accessibilityHidden(true)
            }

            if reveal > 0 {
                content()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.panel, ignoresSafeAreaEdges: [])
                    .overlay(alignment: side == .left ? .trailing : .leading) {
                        Rectangle().fill(AppTheme.border).frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 12 * direction)
                    .offset(x: (reveal - width) * direction)
                    .gesture(closeGesture)
                    .transition(.identity)
            }
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.88), value: isOpen)
    }

    private func close() {
        isOpen = false
        drag = 0
    }

    private var openGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                let travelled = value.predictedEndTranslation.width * direction
                isOpen = travelled > width * 0.35
                drag = 0
            }
    }

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) { drag = value.translation.width }
            }
            .onEnded { value in
                if value.predictedEndTranslation.width * direction < -width * 0.35 { isOpen = false }
                drag = 0
            }
    }
}
