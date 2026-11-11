import SwiftUI

struct ContentDownloadCard: View {
    let packID: String
    @State private var store = ContentStore.shared

    var body: some View {
        if let pack = store.catalog.pack(packID) {
            let course = store.catalog.courses.first { "course-\($0.id)" == packID }
            ContentSelectionCard(
                title: pack.title, packIDs: [packID],
                summary: course.map { "All \($0.lessons.count) lessons, examples and checks, with every required package, dataset and model. Download once, then use the entire course offline." }
                    ?? "The entire Lab topic, with all required packages, datasets and models. Download once, then use every Lab offline.",
                downloadTitle: course == nil ? "Download entire topic" : "Download entire course",
                downloadID: "download-pack-\(packID)")
        } else {
            ContentUnavailableView("Download unavailable", systemImage: "exclamationmark.arrow.triangle.2.circlepath", description: Text("This build does not contain the download catalog. Update Pythilo and try again."))
        }
    }
}

/// One explicit action prepares a complete selection, including shared dependencies.
struct ContentSelectionButton: View {
    let packIDs: [String]
    let title: String
    let downloadID: String
    @State private var store = ContentStore.shared

    var body: some View {
        let packs = store.catalog.closure(packIDs)
        let ready = store.ready(packIDs)
        let busy = packs.contains { [.queued, .downloading, .installing].contains(store.phase($0.id)) }
        let pausable = packs.contains { [.queued, .downloading].contains(store.phase($0.id)) }
        let completed = packs.filter { store.location($0.id) != nil }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { store.download(packIDs) } label: {
                    Label(ready ? "Available offline" : busy ? "Preparing offline…" : "\(title) · \(ByteCountFormatter.string(fromByteCount: Int64(store.missingBytes(packIDs)), countStyle: .file))",
                          systemImage: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ready ? AppTheme.mint : busy ? AppTheme.secondary : AppTheme.onBlue)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(ready ? AppTheme.mint.opacity(0.13) : busy ? AppTheme.raised : AppTheme.blue,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                // A finished download is a state, not a greyed-out action.
                .buttonStyle(SolidButtonStyle()).disabled(ready || busy)
                .accessibilityIdentifier(downloadID)
                if pausable {
                    Button { store.pause(packIDs) } label: {
                        Label("Pause", systemImage: "pause.fill").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.bordered).accessibilityIdentifier("pause-\(downloadID)")
                }
            }
            if !packs.isEmpty {
                Text(ready ? "Complete selection stored on this device for offline use."
                     : "\(completed) of \(packs.count) downloads ready. Offline ready appears only after everything is installed.")
                    .font(.caption).foregroundStyle(AppTheme.secondary)
                    .accessibilityIdentifier("\(ready ? "offline-ready" : "offline-status")-\(downloadID)")
            }
        }
    }
}

struct ContentSelectionCard: View {
    let title: String
    let packIDs: [String]
    let summary: String
    let downloadTitle: String
    let downloadID: String
    @State private var store = ContentStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: store.ready(packIDs) ? "checkmark.circle.fill" : "arrow.down.circle").font(.headline)
            Text(summary).font(.footnote).foregroundStyle(AppTheme.secondary)
            ContentSelectionButton(packIDs: packIDs, title: downloadTitle, downloadID: downloadID)
            ForEach(store.catalog.closure(packIDs)) { DownloadRow(pack: $0) }
            Text("Nothing downloads until you tap Download. Removing downloads keeps your code, lesson drafts and progress.")
                .font(.caption).foregroundStyle(AppTheme.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(cornerRadius: 16)
    }
}

struct ProjectDownloadsView: View {
    let project: Project
    var onClose: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            ContentSelectionCard(title: project.name, packIDs: project.requiredPacks,
                summary: "Download the packages and assets this project needs before going offline. Creating, opening and running a project never starts a download.",
                downloadTitle: "Download project packages", downloadID: "download-project-packages")
                .padding().frame(maxWidth: 760)
            NavigationLink("All downloads") { DownloadsView(onClose: onClose) }
                .accessibilityIdentifier("downloads-all").padding()
        }.accessibilityIdentifier("project-downloads-content")
            .navigationTitle("Project downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { DownloadsCloseButton(onClose: onClose) }
    }
}

private struct DownloadRow: View {
    let pack: ContentPack
    @State private var store = ContentStore.shared
    @State private var confirmRemoval = false
    @State private var failure: String?
    private var size: String { ByteCountFormatter.string(fromByteCount: Int64(pack.bytes), countStyle: .file) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.title).font(.subheadline.weight(.semibold))
                    Text(status).font(.caption).foregroundStyle(AppTheme.secondary)
                }
                Spacer(minLength: 8)
                switch store.phase(pack.id) {
                case .installed:
                    Button("Remove", systemImage: "trash") { confirmRemoval = true }
                        .labelStyle(.iconOnly).accessibilityIdentifier("download-remove-\(pack.id)")
                case .downloading, .queued:
                    Button("Pause", systemImage: "pause.fill") { store.pause(pack.id) }.labelStyle(.iconOnly).accessibilityIdentifier("download-pause-\(pack.id)")
                case .installing: ProgressView()
                case .paused, .failed:
                    Button("Resume", systemImage: "play.fill") { store.download(pack.id) }.labelStyle(.iconOnly).accessibilityIdentifier("download-resume-\(pack.id)")
                    Button("Cancel download", systemImage: "xmark") { store.cancel(pack.id) }.labelStyle(.iconOnly)
                case .absent:
                    Button("Download", systemImage: "arrow.down") { store.download(pack.id) }
                        .labelStyle(.iconOnly).accessibilityIdentifier("download-start-\(pack.id)")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if store.phase(pack.id) == .downloading || store.phase(pack.id) == .paused {
                ProgressView(value: Double(store.received[pack.id] ?? 0), total: Double(pack.bytes))
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(AppTheme.coralInk) }
        }
        .alert("Remove download?", isPresented: $confirmRemoval) {
            Button("Remove download", role: .destructive) { do { try store.remove(pack.id) } catch { failure = error.localizedDescription } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(pack.title) from this device? Your code, lesson drafts and progress will stay.")
        }
    }
    private var status: String {
        switch store.phase(pack.id) {
        case .absent: "Not downloaded · \(size)"
        case .queued: "Queued · \(size)"
        case .downloading: "\(ByteCountFormatter.string(fromByteCount: Int64(store.received[pack.id] ?? 0), countStyle: .file)) of \(size)"
        case .installing: "Verifying and installing…"
        case .paused: "Paused · \(size)"
        case .installed:
            store.ready(pack.id)
                ? "Available offline · \(ByteCountFormatter.string(fromByteCount: Int64(pack.files.reduce(0) { $0 + $1.bytes }), countStyle: .file))"
                : "Saved · required downloads are still missing"
        case .failed(let message): message
        }
    }
}

struct DownloadsView: View {
    var onClose: (() -> Void)? = nil
    @State private var store = ContentStore.shared
    var body: some View {
        List {
            Section {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(store.installedBytes), countStyle: .file)) stored on this device")
                Text("Choose what to download. A course includes all its lessons; a Lab category includes every topic. Each download includes the packages, data and models it needs. After Download completes, use it entirely offline. Nothing downloads automatically.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            }
            Section("Offline library") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("All courses").font(.headline)
                    ContentSelectionButton(packIDs: store.catalog.packs.filter { $0.kind == "course" }.map(\.id), title: "Download all courses", downloadID: "download-all-courses")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("All Labs").font(.headline)
                    ContentSelectionButton(packIDs: store.catalog.packs.filter { $0.kind == "labs" }.map(\.id), title: "Download all Labs", downloadID: "download-all-labs")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Entire library").font(.headline)
                    ContentSelectionButton(packIDs: store.catalog.packs.map(\.id), title: "Download everything", downloadID: "download-everything")
                }
            }
            ForEach([("runtime", "Python packages"), ("asset", "Datasets & models"), ("course", "Courses"), ("labs", "Lab topics")], id: \.0) { kind, title in
                Section(title) {
                    ForEach(store.catalog.packs.filter { $0.kind == kind }) { pack in DownloadRow(pack: pack) }
                }
            }
        }.accessibilityIdentifier("downloads-list")
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { DownloadsCloseButton(onClose: onClose) }
    }
}

private struct DownloadsCloseButton: ToolbarContent {
    var onClose: (() -> Void)?
    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if let onClose {
                Button("Done", action: onClose).accessibilityIdentifier("downloads-close")
            }
        }
    }
}

struct DownloadsSheet: View {
    var project: Project? = nil
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            if let project { ProjectDownloadsView(project: project, onClose: onClose) }
            else { DownloadsView(onClose: onClose) }
        }
        .presentationSizing(.form)
        .presentationDragIndicator(.visible)
    }
}

struct DownloadsLink: View {
    @State private var showingDownloads = false
    var body: some View {
        Button { showingDownloads = true } label: { Label("Downloads", systemImage: "arrow.down.circle") }
            .accessibilityIdentifier("downloads-open")
            .sheet(isPresented: $showingDownloads) { DownloadsSheet(onClose: { showingDownloads = false }) }
    }
}

struct DownloadGate<Content: View>: View {
    let packID: String
    @ViewBuilder var content: () -> Content
    @State private var store = ContentStore.shared
    var body: some View {
        if store.ready(packID) { content() }
        else {
            ScrollView { ContentDownloadCard(packID: packID).padding().frame(maxWidth: 760) }
                .frame(maxWidth: .infinity).background(AppTheme.background)
                .toolbar { DownloadsLink() }
        }
    }
}


/// Presses like any button but does not fade when disabled: the label itself says why.
struct SolidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.interaction, Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The small form of ContentSelectionButton, for a list header: one capsule and a status line.
struct CompactSelectionControl: View {
    let packIDs: [String]
    let title: String
    let downloadID: String
    var readyText = "On this device"
    @State private var store = ContentStore.shared

    var body: some View {
        let packs = store.catalog.closure(packIDs)
        let ready = store.ready(packIDs)
        let busy = packs.contains { [.queued, .downloading, .installing].contains(store.phase($0.id)) }
        let pausable = packs.contains { [.queued, .downloading].contains(store.phase($0.id)) }
        let completed = packs.filter { store.location($0.id) != nil }.count
        if ready {
            // Done is a state, not a button. Tests and VoiceOver read it from this label.
            Label("Offline", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.mint)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(AppTheme.mint.opacity(0.13), in: Capsule())
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel("Available offline. \(readyText)")
                .accessibilityIdentifier("offline-ready-\(downloadID)")
        } else {
            // The status moves under the button when a row is too narrow, instead of overlapping it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    downloadButtons(busy: busy, pausable: pausable, completed: completed, total: packs.count)
                    status(busy: busy, completed: completed, total: packs.count)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { downloadButtons(busy: busy, pausable: pausable, completed: completed, total: packs.count) }
                    status(busy: busy, completed: completed, total: packs.count)
                }
            }
        }
    }

    @ViewBuilder
    private func status(busy: Bool, completed: Int, total: Int) -> some View {
        if busy || completed > 0 {
            Text("\(completed) of \(total) ready")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("offline-status-\(downloadID)")
        }
    }

    @ViewBuilder
    private func downloadButtons(busy: Bool, pausable: Bool, completed: Int, total: Int) -> some View {
        let size = ByteCountFormatter.string(fromByteCount: Int64(store.missingBytes(packIDs)), countStyle: .file)
        Button { store.download(packIDs) } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).tint(AppTheme.blue)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                }
                Text(busy ? "\(completed)/\(total)" : "\(title) · \(size)")
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(busy ? AppTheme.blue : AppTheme.onBlue)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(busy ? AppTheme.selection : AppTheme.blue, in: Capsule())
            .fixedSize()
        }
        .buttonStyle(SolidButtonStyle()).disabled(busy)
        .accessibilityIdentifier(downloadID)
        .accessibilityLabel(busy ? "Preparing offline, \(completed) of \(total) ready" : "\(title), \(size)")
        if pausable {
            Button { store.pause(packIDs) } label: {
                Image(systemName: "pause.fill").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.raised, in: Circle())
            }
            .buttonStyle(SolidButtonStyle())
            .accessibilityLabel("Pause")
            .accessibilityIdentifier("pause-\(downloadID)")
        }
    }
}
