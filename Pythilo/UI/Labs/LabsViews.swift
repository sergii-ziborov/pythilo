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

struct LabsView: View {
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Write the code yourself. Trace runs it line by line and draws every step; How it scales then times it on growing inputs.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondary)
                        .padding(.bottom, 4)
                    ForEach(LabInfo.Section.allCases, id: \.self) { section in
                        let labs = LabCatalog.all.filter { $0.section == section }
                        Text("\(section.rawValue.uppercased()) · \(labs.count)")
                            .sectionLabel()
                            .padding(.top, 10)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
                            ForEach(labs) { lab($0) }
                        }
                    }
                    Text("Timings come from this device. They suggest a growth rate; they do not prove Big O.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Labs")
            .navigationDestination(for: String.self) { id in
                switch id {
                case "graph": GraphLabView()
                case "hash": HashLabView()
                case "dp": DPLabView()
                case "sorting": SortingBenchView()
                default:
                    if let lab = LabCatalog.lab(id), !lab.isClassic { TraceLabView(lab: lab) } else { SortingBenchView() }
                }
            }
            #if DEBUG
            // For screenshots: -openLab <id> [-labVariant <id>] [-labRun YES] [-labAnswer YES] [-labStep 0.6] [-labScale YES].
            .onAppear {
                if path.isEmpty, let lab = UserDefaults.standard.string(forKey: "openLab") { path = [lab] }
            }
            #endif
        }
    }

    private func lab(_ info: LabInfo) -> some View {
        NavigationLink(value: info.id) {
            HStack(spacing: 12) {
                Image(systemName: info.symbol).font(.system(size: 19)).foregroundStyle(info.color).frame(width: 44, height: 44)
                    .background(info.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(.system(size: 16.5, weight: .bold)).foregroundStyle(AppTheme.primary)
                    Text(info.summary).font(.system(size: 13.5)).foregroundStyle(AppTheme.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .panelCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lab-\(info.id)")
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
    @State private var scale: LabScaleResult?
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
                    LabScaleButton(action: runMeasure)
                    if session.isBusy {
                        labButton("Stop", action: session.stop)
                    }
                }

                if let trace { traceView(trace) }
                if let scale { LabScaleCard(result: scale) }

                Text("Trace records every read and write your sort makes to the list. How it scales times it on longer and longer lists.")
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
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "labRun") {
                try? await Task.sleep(for: .seconds(1.5))
                if UserDefaults.standard.bool(forKey: "labScale") { runMeasure() } else { runTrace() }
            }
        }
        #endif
        .navigationTitle("Sorting Bench")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: source) { traceIsStale = trace != nil }
        .onAppear {
            session.onCustom = { kind, data in
                if kind == "lab_trace", let value = try? JSONDecoder().decode(LabTrace.self, from: data) {
                    trace = value
                    step = 0
                    traceIsStale = false
                } else if kind == "lab_scale", let value = try? JSONDecoder().decode(LabScaleResult.self, from: data) {
                    scale = value
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
        session.submit(["kind": "lab_measure", "source": source], label: "scale")
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
}
