import SwiftUI

struct DPLabRepeat: Decodable, Sendable, Identifiable {
    let args: String
    let count: Int
    var id: String { args }
}

struct DPLabWrite: Decodable, Sendable {
    let row: Int
    let column: Int
    let value: Double?

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        row = try container.decode(Int.self)
        column = try container.decode(Int.self)
        value = try container.decodeIfPresent(Double.self)
    }
}

struct DPLabTrace: Decodable, Sendable {
    let problem: String
    let call: String
    let result: String
    let expected: String
    let correct: Bool
    let message: String
    let milliseconds: Double
    let calls: Int
    let distinct: Int
    let deepest: Int
    let repeated: [DPLabRepeat]
    let cacheHits: Int?
    let rows: Int
    let columns: Int
    let writes: [DPLabWrite]
}

struct DPLabView: View {
    enum Problem: String, CaseIterable { case stairs, coins, edit }

    @AppStorage("pythilo.lab.dp.problem") private var problem = Problem.stairs
    @AppStorage("pythilo.lab.dp.stairs") private var stairsSource = Self.templates[.stairs]!
    @AppStorage("pythilo.lab.dp.coins") private var coinsSource = Self.templates[.coins]!
    @AppStorage("pythilo.lab.dp.edit") private var editSource = Self.templates[.edit]!
    @State private var trace: DPLabTrace?
    @State private var write = 0.0
    @State private var measure: LabScaleResult?
    @State private var bridge = EditorKeyboardBridge()
    private let session = RunSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LabChoice(options: [(.stairs, "Stairs"), (.coins, "Coins"), (.edit, "Edit distance")], selection: $problem)
                Text(Self.prompts[problem]!)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondary)
                LabCodeBox(source: source, filePath: "dp.py", height: 200, bridge: bridge)
                HStack(spacing: 8) {
                    LabActionButton(title: "Trace", primary: true, action: runTrace).accessibilityIdentifier("dp-trace")
                    LabScaleButton(action: runMeasure)
                    if session.isBusy { LabActionButton(title: "Stop", action: session.stop) }
                }
                if let trace, trace.problem == problem.rawValue { traceView(trace) }
                if let measure, measure.variant == problem.rawValue { LabScaleCard(result: measure) }
                LabErrors()
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle("Dynamic Programming")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.onCustom = { kind, data in
                if kind == "lab_dp_trace", let value = try? JSONDecoder().decode(DPLabTrace.self, from: data) {
                    trace = value
                    write = Double(max(0, value.writes.count - 1))
                } else if kind == "lab_scale", let value = try? JSONDecoder().decode(LabScaleResult.self, from: data) {
                    measure = value
                }
            }
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "labRun") {
                try? await Task.sleep(for: .seconds(1.5))
                if UserDefaults.standard.bool(forKey: "labScale") { runMeasure() } else { runTrace() }
            }
        }
        #endif
    }

    private var source: Binding<String> {
        switch problem {
        case .stairs: $stairsSource
        case .coins: $coinsSource
        case .edit: $editSource
        }
    }

    private func runTrace() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_dp_trace", "problem": problem.rawValue, "source": source.wrappedValue], label: "trace")
    }

    private func runMeasure() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_dp_measure", "problem": problem.rawValue, "source": source.wrappedValue], label: "scale")
    }

    private func traceView(_ trace: DPLabTrace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(trace.call) = \(trace.result)").font(.system(size: 14, weight: .semibold, design: .monospaced))
            if trace.rows > 0, !trace.writes.isEmpty {
                tableView(trace)
            }
            HStack(spacing: 8) {
                stat("\(trace.calls)", trace.calls == 1 ? "call" : "calls")
                stat("\(trace.distinct)", "distinct")
                stat("\(trace.deepest)", "deepest")
            }
            if let hits = trace.cacheHits {
                Text("The cache answered \(hits) of those calls without running the body.")
                    .font(.system(size: 13.5)).foregroundStyle(AppTheme.secondary)
            } else if let most = trace.repeated.first {
                Text("Most repeated: " + trace.repeated.prefix(3).map { "\($0.args) × \($0.count)" }.joined(separator: ", ") + ". Each repeat redoes work \(most.args) already did once.")
                    .font(.system(size: 13.5)).foregroundStyle(AppTheme.secondary)
            }
            LabVerdict(correct: trace.correct, success: "Correct: \(trace.expected)", message: trace.message)
        }
        .padding(12)
        .panelCard()
    }

    private func tableView(_ trace: DPLabTrace) -> some View {
        let index = min(Int(write), trace.writes.count - 1)
        var cells: [[Double?]] = Array(repeating: Array(repeating: nil, count: trace.columns), count: trace.rows)
        for written in trace.writes.prefix(index + 1) where written.row < trace.rows && written.column < trace.columns {
            cells[written.row][written.column] = written.value
        }
        let current = trace.writes[index]
        let visibleColumns = min(trace.columns, 16)
        let visibleRows = min(trace.rows, 16)
        return VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<visibleRows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<visibleColumns, id: \.self) { column in
                            let isCurrent = current.row == row && current.column == column
                            Text(cells[row][column].map { $0.rounded() == $0 ? "\(Int($0))" : String(format: "%.1f", $0) } ?? "·")
                                .font(.system(size: 11.5, weight: isCurrent ? .heavy : .regular, design: .monospaced))
                                .foregroundStyle(isCurrent ? AppTheme.onRun : cells[row][column] == nil ? AppTheme.muted.opacity(0.5) : AppTheme.primary)
                                .frame(minWidth: 18, maxWidth: 28, minHeight: 22)
                                .background(isCurrent ? AppTheme.run : AppTheme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .accessibilityLabel("Table after write \(index + 1)")
            if trace.writes.count > 1 {
                Slider(value: $write, in: 0...Double(trace.writes.count - 1), step: 1).tint(AppTheme.run)
            }
            HStack {
                Text("Write \(index + 1) of \(trace.writes.count)")
                Spacer()
                Text("dp[\(current.row)][\(current.column)]")
            }
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(AppTheme.secondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 20, weight: .bold))
            Text(label).font(.system(size: 12)).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .panelCard(cornerRadius: 12)
    }

    static let prompts: [Problem: String] = [
        .stairs: "ways(n): how many ways to climb n stairs, one or two at a time. Trace it, then try @cache from functools.",
        .coins: "min_coins(amount): the fewest coins of 1, 3 and 4 that add up to amount. Greedy is not enough here.",
        .edit: "edit_distance(a, b): the fewest inserts, deletes and replacements. table(rows, columns) gives a grid the lab can show.",
    ]

    static let templates: [Problem: String] = [
        .stairs: """
        def ways(n):
            if n < 2:
                return 1
            return ways(n - 1) + ways(n - 2)

        """,
        .coins: """
        def min_coins(amount):
            if amount == 0:
                return 0
            return 1 + min(min_coins(amount - coin) for coin in (1, 3, 4) if coin <= amount)

        """,
        .edit: """
        def edit_distance(a, b):
            dp = table(len(a) + 1, len(b) + 1)
            for i in range(len(a) + 1):
                dp[i][0] = i
            for j in range(len(b) + 1):
                dp[0][j] = j
            for i in range(1, len(a) + 1):
                for j in range(1, len(b) + 1):
                    cost = 0 if a[i - 1] == b[j - 1] else 1
                    dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            return dp[len(a)][len(b)]

        """,
    ]
}
