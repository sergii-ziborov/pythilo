import SwiftUI
import WebKit

struct WebPreview: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    var backToken = 0
    /// The path the page reached by its own links, for the address field.
    var onNavigate: (String) -> Void = { _ in }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var token = -1
        var back = 0
        var onNavigate: (String) -> Void = { _ in }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            onNavigate(url.path() + (url.query().map { "?" + $0 } ?? ""))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        // Pages without their own background read as they would in a browser.
        view.isOpaque = true
        view.backgroundColor = .white
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        if context.coordinator.back != backToken {
            context.coordinator.back = backToken
            if view.canGoBack { view.goBack() }
            return
        }
        guard context.coordinator.token != reloadToken else { return }
        context.coordinator.token = reloadToken
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }
}

/// The site the project serves, with its path editable: /admin/, /tasks.
struct PreviewColumn: View {
    let url: URL
    @State private var path = "/"
    @State private var target: URL?
    @State private var reloads = 0
    @State private var backs = 0
    @FocusState private var editing: Bool

    private var origin: String { "\(url.host() ?? "127.0.0.1"):\(url.port ?? 80)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { backs += 1 } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 44)
                }
                .buttonStyle(.app)
                .accessibilityLabel("Back")
                Circle().fill(AppTheme.mint).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(origin)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .fixedSize()
                TextField("/", text: $path)
                    .font(.system(size: 13.5, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($editing)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Path on the site")
                    .accessibilityIdentifier("preview-path")
                    .onSubmit(go)
                Button {
                    reloads += 1
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .buttonStyle(.app)
                .accessibilityLabel("Reload")
            }
            .padding(.leading, 4)
            .padding(.trailing, 6)
            .frame(height: 50)
            Rectangle().fill(AppTheme.border).frame(height: 1)
            WebPreview(url: target ?? url, reloadToken: reloads, backToken: backs) { reached in
                if !editing { path = reached.isEmpty ? "/" : reached }
            }
        }
        .background(AppTheme.panel, ignoresSafeAreaEdges: [])
        .onAppear { path = url.path().isEmpty ? "/" : url.path() }
    }

    private func go() {
        let typed = path.trimmingCharacters(in: .whitespaces)
        let relative = typed.hasPrefix("/") ? typed : "/" + typed
        target = URL(string: "http://\(origin)\(relative)")
        reloads += 1
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
