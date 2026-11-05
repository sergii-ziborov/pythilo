import SwiftUI

struct HashLabResult: Decodable, Sendable {
    let workload: String
    let count: Int
    let buckets: [Int]
    let bucketCount: Int
    let longest: Int
    let empty: Int
    let averageProbes: Double
    let mostProbes: Int
    let tableMs: Double
    let dictMs: Double
    let correct: Bool
    let message: String
}

struct HashLabView: View {
    @AppStorage("pythilo.lab.hash") private var source = Self.template
    @AppStorage("pythilo.lab.hash.workload") private var workload = "words"
    @State private var result: HashLabResult?
    @State private var scale: LabScaleResult?
    @State private var bridge = EditorKeyboardBridge()
    private let session = RunSession.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Write class Table with put(key, value) and get(key). Keep its slots in self.buckets so the lab can draw them.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.secondary)
                LabCodeBox(source: $source, filePath: "table.py", height: 230, bridge: bridge)
                ScrollView(.horizontal, showsIndicators: false) {
                    LabChips(options: [("words", "Words"), ("sequential", "Sequential"), ("random", "Random"), ("colliding", "Colliding")], selection: $workload)
                }
                HStack(spacing: 8) {
                    LabActionButton(title: "Run 400 keys", primary: true, action: run).accessibilityIdentifier("hash-run")
                    LabScaleButton(action: runScale)
                    if session.isBusy { LabActionButton(title: "Stop", action: session.stop) }
                }
                if let result, result.workload == workload { resultView(result) }
                if let scale, scale.variant == workload { LabScaleCard(result: scale) }
                Text("Comparisons are counted by the keys themselves, so the count is right whatever your table does inside.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondary)
                LabErrors()
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle("Search & Hashing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            session.onCustom = { kind, data in
                if kind == "lab_hash", let value = try? JSONDecoder().decode(HashLabResult.self, from: data) {
                    result = value
                } else if kind == "lab_scale", let value = try? JSONDecoder().decode(LabScaleResult.self, from: data) {
                    scale = value
                }
            }
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "labRun") {
                try? await Task.sleep(for: .seconds(1.5))
                if UserDefaults.standard.bool(forKey: "labScale") { runScale() } else { run() }
            }
        }
        #endif
    }

    private func runScale() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_hash_scale", "source": source, "workload": workload], label: "scale")
    }

    private func run() {
        bridge.dismissKeyboard()
        session.clearOutput()
        session.submit(["kind": "lab_hash", "source": source, "workload": workload, "count": 400], label: "hash")
    }

    @ViewBuilder
    private func resultView(_ result: HashLabResult) -> some View {
        if !result.buckets.isEmpty {
            let shown = Array(result.buckets.prefix(64))
            let top = max(1, shown.max() ?? 1)
            // Red marks a bucket holding over twice its fair share.
            let crowded = max(2, 2 * Double(result.count) / Double(max(1, result.bucketCount)))
            VStack(alignment: .leading, spacing: 8) {
                Text("\(result.bucketCount) BUCKETS AFTER \(result.count) PUTS").sectionLabel()
                HStack(alignment: .bottom, spacing: shown.count > 32 ? 1 : 3) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, length in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(length == 0 ? AppTheme.border : Double(length) > crowded ? AppTheme.coral : AppTheme.blue)
                            .frame(height: max(2, 110 * CGFloat(length) / CGFloat(top)))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 112)
                .accessibilityLabel("Bucket sizes, the longest holds \(result.longest)")
                if result.bucketCount > shown.count {
                    Text("Showing the first \(shown.count) of \(result.bucketCount) buckets.").font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
                }
                if result.workload == "colliding", result.longest * 2 > result.count {
                    Text("Every key is a multiple of \(result.bucketCount), so hash(key) % \(result.bucketCount) puts them in one bucket.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(AppTheme.secondary)
                }
            }
            .padding(12)
            .panelCard()
        }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            stat(String(format: "%.1f", result.averageProbes), "key comparisons per get", alarming: result.averageProbes > 8)
            stat("\(result.longest)", "longest bucket")
            stat("\(result.empty)", "empty buckets")
            stat(String(format: "%.1f ms", result.tableMs), String(format: "400 puts and gets · dict %.2f ms", result.dictMs))
        }
        LabVerdict(correct: result.correct, success: "Every get returned what was put, and a missing key raised KeyError", message: result.message)
    }

    private func stat(_ value: String, _ label: String, alarming: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(alarming ? AppTheme.coralInk : AppTheme.primary)
            Text(label).font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .panelCard(cornerRadius: 12)
    }

    static let template = """
    class Table:
        def __init__(self, size=16):
            self.buckets = [[] for _ in range(size)]

        def _bucket(self, key):
            return self.buckets[hash(key) % len(self.buckets)]

        def put(self, key, value):
            bucket = self._bucket(key)
            for i, (k, _) in enumerate(bucket):
                if k == key:
                    bucket[i] = (key, value)
                    return
            bucket.append((key, value))

        def get(self, key):
            for k, v in self._bucket(key):
                if k == key:
                    return v
            raise KeyError(key)

    """
}
