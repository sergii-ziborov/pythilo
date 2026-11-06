import SwiftUI

struct NotebookCell: Identifiable {
    let id: String
    var kind: String
    var source: String
    var outputs: [[String: Any]]
    var executionCount: Int?
    var ranSource: String?
    var running = false
    /// Keys Pythilo does not edit, kept so saving does not lose them.
    var extra: [String: Any]

    var isStale: Bool {
        kind == "code" && ranSource != nil && ranSource != source
    }
}

/// An ordinary .ipynb, read and written as Jupyter's own JSON.
@MainActor
@Observable
final class NotebookDocument {
    let url: URL
    private(set) var cells: [NotebookCell] = []
    private(set) var failure: String?
    private var root: [String: Any] = [:]
    private var save: Task<Void, Never>?

    init(url: URL) {
        self.url = url
        load()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw WorkspaceFailure("This is not a notebook.")
            }
            root = object
            cells = ((object["cells"] as? [[String: Any]]) ?? []).map { cell in
                let source: String
                if let lines = cell["source"] as? [String] {
                    source = lines.joined()
                } else {
                    source = cell["source"] as? String ?? ""
                }
                var extra = cell
                for key in ["source", "outputs", "execution_count", "cell_type"] { extra[key] = nil }
                return NotebookCell(
                    id: cell["id"] as? String ?? UUID().uuidString,
                    kind: cell["cell_type"] as? String ?? "code",
                    source: source,
                    outputs: cell["outputs"] as? [[String: Any]] ?? [],
                    executionCount: cell["execution_count"] as? Int,
                    extra: extra
                )
            }
        } catch {
            failure = "Could not read this notebook: \(error.localizedDescription)"
        }
    }

    func saveNow() {
        guard failure == nil else { return }
        var object = root
        object["cells"] = cells.map { cell -> [String: Any] in
            var entry = cell.extra
            entry["id"] = cell.id
            entry["cell_type"] = cell.kind
            entry["source"] = Self.lines(cell.source)
            if cell.kind == "code" {
                entry["outputs"] = cell.outputs
                entry["execution_count"] = cell.executionCount ?? NSNull()
            }
            return entry
        }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Jupyter keeps source as a list of lines that each hold their newline.
    private static func lines(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "\n" {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func scheduleSave() {
        save?.cancel()
        save = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func setSource(_ source: String, for id: String) {
        guard let index = cells.firstIndex(where: { $0.id == id }), cells[index].source != source else { return }
        cells[index].source = source
        scheduleSave()
    }

    func add(kind: String) {
        cells.append(NotebookCell(id: UUID().uuidString, kind: kind, source: "", outputs: [], extra: ["metadata": [String: Any]()]))
        scheduleSave()
    }

    func remove(_ id: String) {
        cells.removeAll { $0.id == id }
        scheduleSave()
    }

    func move(_ id: String, by offset: Int) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard cells.indices.contains(target) else { return }
        cells.swapAt(index, target)
        scheduleSave()
    }

    func clearOutputs() {
        for index in cells.indices {
            cells[index].outputs = []
            cells[index].executionCount = nil
            cells[index].ranSource = nil
        }
        scheduleSave()
    }

    func begin(_ id: String) {
        guard let index = cells.firstIndex(where: { $0.id == id }) else { return }
        cells[index].outputs = []
        cells[index].running = true
        cells[index].ranSource = cells[index].source
    }

    func receive(_ event: CellEvent) {
        switch event {
        case let .started(cell, count):
            if let index = cells.firstIndex(where: { $0.id == cell }) { cells[index].executionCount = count }
        case let .output(cell, json):
            guard let index = cells.firstIndex(where: { $0.id == cell }),
                  let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return }
            append(object, at: index)
        case let .ended(cell, _):
            if let index = cells.firstIndex(where: { $0.id == cell }) { cells[index].running = false }
            scheduleSave()
        }
    }

    func finishAll() {
        for index in cells.indices { cells[index].running = false }
        scheduleSave()
    }

    private func append(_ event: [String: Any], at index: Int) {
        let type = event["type"] as? String ?? "stream"
        switch type {
        case "stream":
            let name = event["name"] as? String ?? "stdout"
            let text = event["text"] as? String ?? ""
            if let last = cells[index].outputs.indices.last,
               cells[index].outputs[last]["output_type"] as? String == "stream",
               cells[index].outputs[last]["name"] as? String == name,
               let previous = cells[index].outputs[last]["text"] as? [String] {
                cells[index].outputs[last]["text"] = [previous.joined() + text]
            } else {
                cells[index].outputs.append(["output_type": "stream", "name": name, "text": [text]])
            }
        case "execute_result":
            cells[index].outputs.append([
                "output_type": "execute_result",
                "execution_count": event["count"] ?? NSNull(),
                "data": event["data"] ?? [String: Any](),
                "metadata": [String: Any](),
            ])
        case "display_data":
            cells[index].outputs.append(["output_type": "display_data", "data": event["data"] ?? [String: Any](), "metadata": [String: Any]()])
        default:
            cells[index].outputs.append([
                "output_type": "error",
                "ename": event["ename"] ?? "",
                "evalue": event["evalue"] ?? "",
                "traceback": event["traceback"] ?? [String](),
            ])
        }
    }
}

struct NotebookView: View {
    @Bindable var model: WorkspaceModel
    let path: String
    @State private var document: NotebookDocument?
    @State private var queue: [String] = []
    @State private var currentCell: String?

    private var session: RunSession { model.session }

    var body: some View {
        Group {
            if let document {
                content(document)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            let doc = NotebookDocument(url: model.fileURL(path))
            document = doc
            session.onCell = { [weak doc] event in doc?.receive(event) }
        }
        .onDisappear {
            document?.saveNow()
        }
        .onChange(of: session.phase) { _, phase in
            guard phase == .idle, currentCell != nil else { return }
            currentCell = nil
            document?.finishAll()
            if session.lastOutcome?.status == "cancelled" {
                queue = []
            } else {
                runNext()
            }
        }
    }

    private func content(_ document: NotebookDocument) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if let failure = document.failure {
                    Text(failure).foregroundStyle(AppTheme.coralInk).padding()
                }
                HStack(spacing: 6) {
                    Button("Run all", systemImage: "play.fill") { runAll(document) }
                        .accessibilityIdentifier("notebook-run-all")
                    Spacer()
                    Button("Restart", systemImage: "arrow.clockwise") { restart(document) }
                    Button("Clear", systemImage: "eraser") { document.clearOutputs() }
                }
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .disabled(session.isBusy)
                ForEach(document.cells) { cell in
                    CellView(
                        cell: cell,
                        onChange: { document.setSource($0, for: cell.id) },
                        onRun: { run(cell.id, document) },
                        onDelete: { document.remove(cell.id) },
                        onMove: { document.move(cell.id, by: $0) },
                        busy: session.isBusy
                    )
                }
                HStack(spacing: 8) {
                    addButton("Add code") { document.add(kind: "code") }
                    addButton("Add text") { document.add(kind: "markdown") }
                }
            }
            .padding(10)
            .padding(.bottom, 60)
        }
    }

    private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.app)
    }

    private func restart(_ document: NotebookDocument) {
        document.clearOutputs()
        session.submit(["kind": "notebook_reset", "path": model.fileURL(path).path, "root": model.project.url.path], label: "restart")
    }

    private func runAll(_ document: NotebookDocument) {
        queue = document.cells.filter { $0.kind == "code" }.map(\.id)
        runNext()
    }

    private func runNext() {
        guard let document, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        run(next, document)
    }

    private func run(_ id: String, _ document: NotebookDocument) {
        guard session.phase == .idle, let cell = document.cells.first(where: { $0.id == id }) else { return }
        document.begin(id)
        currentCell = id
        session.submit(
            [
                "kind": "notebook",
                "cell": id,
                "path": model.fileURL(path).path,
                "source": cell.source,
                "root": model.project.url.path,
                "cwd": model.project.url.path,
            ],
            label: "cell"
        )
    }
}

private struct CellView: View {
    let cell: NotebookCell
    let onChange: (String) -> Void
    let onRun: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void
    let busy: Bool
    @State private var text: String
    @State private var editingMarkdown = false
    @FocusState private var focused: Bool

    init(cell: NotebookCell, onChange: @escaping (String) -> Void, onRun: @escaping () -> Void, onDelete: @escaping () -> Void, onMove: @escaping (Int) -> Void, busy: Bool) {
        self.cell = cell
        self.onChange = onChange
        self.onRun = onRun
        self.onDelete = onDelete
        self.onMove = onMove
        self.busy = busy
        _text = State(initialValue: cell.source)
    }

    var body: some View {
        if cell.kind == "markdown", !editingMarkdown, !cell.source.isEmpty {
            Text(MarkdownRenderer.attributed(cell.source))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .onTapGesture { editingMarkdown = true }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(cell.kind == "code" ? "[\(cell.executionCount.map(String.init) ?? " ")]" : "text")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(AppTheme.muted)
                    if cell.isStale {
                        Text("Edited after it ran").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(AppTheme.amber)
                    }
                    if cell.running { ProgressView().controlSize(.mini) }
                    Spacer()
                    Menu {
                        Button("Move up", systemImage: "arrow.up") { onMove(-1) }
                        Button("Move down", systemImage: "arrow.down") { onMove(1) }
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 40, height: 32).foregroundStyle(AppTheme.muted)
                    }
                    if cell.kind == "code" {
                        Button(action: onRun) {
                            Image(systemName: "play.fill").font(.system(size: 12)).foregroundStyle(AppTheme.run).frame(width: 44, height: 32)
                                .background(Color.black.opacity(0.001))
                        }
                        .buttonStyle(.app)
                        .disabled(busy)
                        .accessibilityLabel("Run cell")
                    }
                }
                .padding(.leading, 10)
                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .onChange(of: text) { onChange(text) }
                    .onChange(of: focused) { if !focused, cell.kind == "markdown" { editingMarkdown = false } }
                ForEach(Array(cell.outputs.enumerated()), id: \.offset) { _, output in
                    OutputBlock(output: output)
                }
            }
            .panelCard(cornerRadius: 12)
            .overlay {
                if focused { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.blue, lineWidth: 1) }
            }
        }
    }
}

private struct OutputBlock: View {
    let output: [String: Any]

    private func text(_ value: Any?) -> String {
        if let lines = value as? [String] { return lines.joined() }
        return value as? String ?? ""
    }

    var body: some View {
        let type = output["output_type"] as? String
        VStack(alignment: .leading, spacing: 6) {
            switch type {
            case "stream":
                Text(text(output["text"]))
                    .foregroundStyle(output["name"] as? String == "stderr" ? AppTheme.coralInk : AppTheme.secondary)
            case "error":
                Text(text(output["traceback"]).isEmpty ? "\(text(output["ename"])): \(text(output["evalue"]))" : text(output["traceback"]))
                    .foregroundStyle(AppTheme.coralInk)
            default:
                let data = output["data"] as? [String: Any] ?? [:]
                if let encoded = data["image/png"] as? String,
                   let bytes = Data(base64Encoded: encoded.replacingOccurrences(of: "\n", with: "")),
                   let image = UIImage(data: bytes) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).background(Color.white)
                        .accessibilityLabel(text(data["text/plain"]))
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        if type == "execute_result" { Text("Out").foregroundStyle(AppTheme.amber) }
                        Text(text(data["text/plain"])).foregroundStyle(AppTheme.secondary)
                    }
                }
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }
}
