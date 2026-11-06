import SwiftUI

struct ContentDownloadCard: View {
    let packID: String
    @State private var store = ContentStore.shared

    var body: some View {
        if let pack = store.catalog.pack(packID) {
            VStack(alignment: .leading, spacing: 12) {
                Label(pack.title, systemImage: store.ready(packID) ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.headline)
                Text("Download once to use offline. Removing a download keeps your code, drafts and progress.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
                ForEach(store.catalog.closure(packID)) { entry in
                    DownloadRow(pack: entry)
                }
                if !store.ready(packID) {
                    Button {
                        store.download(packID)
                    } label: {
                        Text("Download missing · \(ByteCountFormatter.string(fromByteCount: Int64(store.missingBytes(packID)), countStyle: .file))")
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("download-pack-\(packID)")
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panelCard(cornerRadius: 16)
        } else {
            ContentUnavailableView("Download unavailable", systemImage: "exclamationmark.arrow.triangle.2.circlepath", description: Text("This build does not contain the download catalog. Update Pythilo and try again."))
        }
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
                    Button("Remove", systemImage: "trash") { confirmRemoval = true }.labelStyle(.iconOnly)
                case .downloading, .queued:
                    Button("Pause", systemImage: "pause.fill") { store.pause(pack.id) }.labelStyle(.iconOnly).accessibilityIdentifier("download-pause-\(pack.id)")
                case .installing: ProgressView()
                case .paused, .failed:
                    Button("Resume", systemImage: "play.fill") { store.download(pack.id) }.labelStyle(.iconOnly).accessibilityIdentifier("download-resume-\(pack.id)")
                    Button("Cancel download", systemImage: "xmark") { store.cancel(pack.id) }.labelStyle(.iconOnly)
                case .absent:
                    Button("Download", systemImage: "arrow.down") { store.download(pack.id) }.labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if store.phase(pack.id) == .downloading || store.phase(pack.id) == .paused {
                ProgressView(value: Double(store.received[pack.id] ?? 0), total: Double(pack.bytes))
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(AppTheme.coralInk) }
        }
        .confirmationDialog("Remove \(pack.title)? Your code and progress will stay on this device.", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove download", role: .destructive) { do { try store.remove(pack.id) } catch { failure = error.localizedDescription } }
        }
    }
    private var status: String {
        switch store.phase(pack.id) {
        case .absent: "\(size) download"
        case .queued: "Queued · \(size)"
        case .downloading: "\(ByteCountFormatter.string(fromByteCount: Int64(store.received[pack.id] ?? 0), countStyle: .file)) of \(size)"
        case .installing: "Verifying and installing…"
        case .paused: "Paused · \(size)"
        case .installed: "Available offline · \(ByteCountFormatter.string(fromByteCount: Int64(pack.files.reduce(0) { $0 + $1.bytes }), countStyle: .file))"
        case .failed(let message): message
        }
    }
}

struct DownloadsView: View {
    @State private var store = ContentStore.shared
    var body: some View {
        List {
            Section {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(store.installedBytes), countStyle: .file)) stored on this device")
                Text("Project code stays local. Download courses, Lab topics and Python packages when needed. Compiled Python backends are part of the signed app.")
                    .font(.footnote).foregroundStyle(AppTheme.secondary)
            }
            ForEach([("runtime", "Python packages"), ("asset", "Datasets & models"), ("course", "Courses"), ("labs", "Lab topics")], id: \.0) { kind, title in
                Section(title) {
                    ForEach(store.catalog.packs.filter { $0.kind == kind }) { pack in DownloadRow(pack: pack) }
                }
            }
        }.navigationTitle("Downloads")
    }
}

struct DownloadsLink: View {
    var body: some View {
        NavigationLink { DownloadsView() } label: { Label("Downloads", systemImage: "arrow.down.circle") }
            .accessibilityIdentifier("downloads-open")
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
