import SwiftUI
import WebKit

struct WebPreview: UIViewRepresentable {
    let url: URL
    let reloadToken: Int

    final class Coordinator {
        var token = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.token != reloadToken else { return }
        context.coordinator.token = reloadToken
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }
}

struct PreviewColumn: View {
    let url: URL
    @State private var reloads = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(AppTheme.mint).frame(width: 8, height: 8)
                Text(url.absoluteString.replacingOccurrences(of: "http://", with: ""))
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    reloads += 1
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reload")
            }
            .padding(.leading, 12)
            .frame(height: 50)
            Rectangle().fill(AppTheme.border).frame(height: 1)
            WebPreview(url: url, reloadToken: reloads)
        }
        .background(AppTheme.panel, ignoresSafeAreaEdges: [])
    }
}

struct PreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WorkspaceModel

    var body: some View {
        NavigationStack {
            Group {
                if let url = model.previewURL {
                    VStack(spacing: 0) {
                        PreviewColumn(url: url)
                        Rectangle().fill(AppTheme.border).frame(height: 1)
                        OutputTextView(chunks: model.session.terminalOutput, revision: model.session.terminalRevision, fontSize: 12.5)
                            .frame(height: 128)
                            .background(AppTheme.panel, ignoresSafeAreaEdges: [])
                    }
                } else {
                    ContentUnavailableView("The server has stopped", systemImage: "globe")
                }
            }
            .navigationTitle("Web preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Stop server", role: .destructive) { model.session.stop() }
                }
            }
        }
    }
}
