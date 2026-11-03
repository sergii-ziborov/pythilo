import SwiftUI

struct LabStep: Decodable, Sendable {
    let kind: String
    let i: [Int]
    let values: [Int]
}

struct LabTrace: Decodable, Sendable {
    let id: String
    let steps: [LabStep]
    let correct: Bool
    let truncated: Bool
}

struct LabCell: Decodable, Sendable {
    let median: Double
    let spread: Double
    let correct: Bool
}

struct LabRow: Decodable, Sendable, Identifiable {
    let name: String
    let cells: [String: LabCell]
    var id: String { name }
}

struct LabMeasure: Decodable, Sendable {
    let id: String
    let size: Int
    let rows: [LabRow]
}

struct LabsView: View {
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your own code, traced while it runs and measured on this device. Correctness first, then time.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                        .padding(.bottom, 4)
                    lab("Sorting Bench", "Trace your sort read by read, then time it on four inputs", "chart.bar.fill", AppTheme.run, id: "sorting")
                    lab("Graph Explorer", "Watch your BFS, DFS or Dijkstra expand a grid, tree or random graph", "point.3.connected.trianglepath.dotted", AppTheme.blue, id: "graph")
                    lab("Search & Hashing", "Build a hash table and see buckets fill and keys collide", "square.stack.3d.up.fill", AppTheme.mint, id: "hash")
                    lab("Dynamic Programming", "Count repeated calls, add a cache, fill the table cell by cell", "tablecells", AppTheme.violet, id: "dp")
                    Text("Timings come from this device. They suggest a growth rate; they do not prove Big O.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Labs")
            .navigationDestination(for: String.self) { lab in
                switch lab {
                case "graph": GraphLabView()
                case "hash": HashLabView()
                case "dp": DPLabView()
                default: SortingBenchView()
                }
            }
            #if DEBUG
            // For screenshots: -openLab graph|hash|dp|sorting, -labRun YES.
            .onAppear {
                if path.isEmpty, let lab = UserDefaults.standard.string(forKey: "openLab") { path = [lab] }
            }
            #endif
        }
    }

    private func lab(_ title: String, _ summary: String, _ symbol: String, _ tint: Color, id: String) -> some View {
        NavigationLink(value: id) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(tint).frame(width: 44, height: 44)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16.5, weight: .bold))
                    Text(summary).font(.system(size: 13.5)).foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            .padding(12)
            .panelCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lab-\(id)")
    }
}

struct SortingBenchView: View {
    @AppStorage("pythilo.lab.sort") private var source = """
    def my_sort(items):
        for i in range(1, len(items)):
            key = items[i]
            j = i - 1
            while j >= 0 and items[j] > key:
                items[j + 1] = items[j]
                j -= 1
            items[j + 1] = key

    """
    @State private var cursor = 0
    @State private var trace: LabTrace?
    @State private var step = 0.0
    @State private var measure: LabMeasure?
    @State private var traceIsStale = false
    @State private var bridge = EditorKeyboardBridge()
    private let session = RunSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your own code, traced while it runs. Define my_sort(items), which sorts the list in place.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.secondary)
                SyntaxCodeEditor(
                    text: $source,
                    cursorOffset: $cursor,
                    filePath: "sort.py",
                    isEditable: !session.isBusy,
                    tracksTyping: false,
                    navigationTarget: nil,
                    keyboardBridge: bridge,
                    onRequestCompletion: {}
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }

                HStack(spacing: 8) {
                    labButton("Trace", primary: true, action: runTrace).accessibilityIdentifier("lab-trace")
                    labButton("Measure", action: runMeasure).accessibilityIdentifier("lab-measure")
                    if session.isBusy {
                        labButton("Stop", action: session.stop)
                    }
                }

                if let trace { traceView(trace) }
                if let measure { measureView(measure) }

                Text("Times are measured without the tracer. A chart from one device suggests a growth rate. It does not prove Big O.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondary)

                ForEach(session.output.filter { $0.kind == .stderr }) { chunk in
                    Text(chunk.text).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(AppTheme.coralInk)
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle("Sorting Bench")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: source) { traceIsStale = trace != nil }
        .onAppear {
            session.onCustom = { kind, data in
                if kind == "lab_trace", let value = try? JSONDecoder().decode(LabTrace.self, from: data) {
                    trace = value
                    step = 0
                    traceIsStale = false
                } else if kind == "lab_measure", let value = try? JSONDecoder().decode(LabMeasure.self, from: data) {
                    measure = value
                }
            }
        }
    }

    private func labButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(primary ? AppTheme.onRun : AppTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(primary ? AppTheme.run : AppTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(.plain)
            .disabled(session.isBusy && title != "Stop")
    }

    private func runTrace() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_trace", "source": source], label: "trace")
    }

    private func runMeasure() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_measure", "source": source, "size": 2000, "runs": 5], label: "measure")
    }

    private func traceView(_ trace: LabTrace) -> some View {
        let index = min(Int(step), trace.steps.count - 1)
        let current = trace.steps[index]
        let top = max(1, current.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(current.values.enumerated()), id: \.offset) { position, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(current.i.contains(position) ? (current.kind == "write" ? AppTheme.coral : AppTheme.run) : AppTheme.blue.opacity(0.7))
                        .frame(height: 120 * CGFloat(value) / CGFloat(top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 124)
            .accessibilityLabel("Bars at step \(index + 1)")
            Slider(value: $step, in: 0...Double(max(1, trace.steps.count - 1)), step: 1)
                .tint(AppTheme.run)
                .accessibilityIdentifier("lab-step")
            HStack {
                Text("Step \(index + 1) of \(trace.steps.count)")
                Spacer()
                Text(current.kind == "write" ? "write [\(current.i.first ?? 0)]" : current.kind == "read" ? "read [\(current.i.first ?? 0)]" : "start")
            }
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(AppTheme.secondary)
            if traceIsStale {
                Text("You changed the code. This trace is from the earlier version. Trace again.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.amber)
            } else if !trace.correct {
                Text("The list did not end up sorted.").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.coralInk)
            }
            if trace.truncated {
                Text("Stopped recording at \(trace.steps.count) steps.").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .panelCard()
    }

    private func measureView(_ measure: LabMeasure) -> some View {
        let kinds = ["random", "sorted", "reversed", "duplicates"]
        return VStack(alignment: .leading, spacing: 6) {
            Text("MEASURED ON THIS DEVICE, \(measure.size) ITEMS, 5 RUNS, MEDIAN MS").sectionLabel()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(kinds, id: \.self) { Text($0).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(AppTheme.muted) }
                }
                ForEach(measure.rows) { row in
                    GridRow {
                        Text(row.name).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        ForEach(kinds, id: \.self) { kind in
                            let cell = row.cells[kind]
                            Text(cell.map { $0.correct ? String(format: "%.2f", $0.median) : "wrong" } ?? "")
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(cell?.correct == false ? AppTheme.coralInk : AppTheme.primary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .panelCard()
    }
}
