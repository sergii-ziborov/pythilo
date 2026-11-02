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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink {
                        SortingBenchView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.fill").font(.system(size: 20)).foregroundStyle(AppTheme.run).frame(width: 40, height: 40)
                                .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sorting Bench").font(.system(size: 16, weight: .semibold))
                                Text("Trace your own sort step by step, then measure it").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                        }
                        .padding(12)
                        .panelCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lab-sorting")
                    Text("Graphs, hashing and dynamic programming labs are not built yet.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Labs")
        }
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
