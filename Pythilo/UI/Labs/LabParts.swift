import Charts
import SwiftUI

/// The editor every lab puts its code in.
struct LabCodeBox: View {
    @Binding var source: String
    let filePath: String
    var height: CGFloat = 200
    let bridge: EditorKeyboardBridge
    private let session = RunSession.shared
    @State private var cursor = 0

    var body: some View {
        SyntaxCodeEditor(
            text: $source,
            cursorOffset: $cursor,
            filePath: filePath,
            isEditable: !session.isBusy,
            tracksTyping: false,
            wrapsLines: true,
            navigationTarget: nil,
            keyboardBridge: bridge,
            onRequestCompletion: {}
        )
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
    }
}

struct LabActionButton: View {
    let title: String
    var primary = false
    let action: () -> Void
    private let session = RunSession.shared

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(primary ? AppTheme.onRun : AppTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(primary ? AppTheme.run : AppTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            .buttonStyle(.plain)
            .disabled(session.isBusy && title != "Stop")
    }
}

/// A row of choices that reads as one control, like the lesson mode switch.
struct LabChoice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                Button(title) { selection = value }
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(selection == value ? AppTheme.primary : AppTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(selection == value ? AppTheme.raised : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Smaller choices for inputs: topology, workload.
struct LabChips<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, title in
                Button(title) { selection = value }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(selection == value ? AppTheme.selectionInk : AppTheme.secondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(selection == value ? AppTheme.selection : .clear, in: Capsule())
                    .overlay { if selection != value { Capsule().stroke(AppTheme.border, lineWidth: 1) } }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}

/// Green when the user's code got the right answer, red with the reason when not.
struct LabVerdict: View {
    let correct: Bool
    let success: String
    let message: String

    var body: some View {
        Text(correct ? success : message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(correct ? AppTheme.mint : AppTheme.coralInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(correct ? AppTheme.mint.opacity(0.12) : AppTheme.dangerPanel, in: RoundedRectangle(cornerRadius: 12))
            .textSelection(.enabled)
    }
}

/// Errors the lab could not turn into a result, such as a syntax error.
struct LabErrors: View {
    private let session = RunSession.shared

    var body: some View {
        ForEach(session.output.filter { $0.kind == .stderr }) { chunk in
            Text(chunk.text).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(AppTheme.coralInk)
        }
    }
}

/// What "How it scales" ran, a chart of time against input size, and a one-line reading of it.
struct LabScaleCard: View {
    let result: LabScaleResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW IT SCALES").sectionLabel()
            if !result.what.isEmpty {
                Text(whatRan).font(.system(size: 13.5)).foregroundStyle(AppTheme.secondary)
            }
            if result.series.contains(where: { !$0.points.isEmpty }) {
                Chart {
                    ForEach(result.series) { series in
                        ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                            if point.count == 2 {
                                LineMark(x: .value(result.x, point[0]), y: .value("ms", point[1]))
                                    .foregroundStyle(by: .value("code", series.name))
                                PointMark(x: .value(result.x, point[0]), y: .value("ms", point[1]))
                                    .foregroundStyle(by: .value("code", series.name))
                                    .symbolSize(22)
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(range: [AppTheme.coral, AppTheme.blue, AppTheme.violet, AppTheme.mint, AppTheme.amber])
                .chartXAxisLabel(result.x)
                .chartYAxisLabel("ms")
                .chartLegend(result.series.count > 1 ? .visible : .hidden)
                .frame(height: 190)
                .accessibilityLabel(result.takeaway.isEmpty ? "Time against input size" : result.takeaway)
            }
            if !result.takeaway.isEmpty {
                Text(result.takeaway)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
                    .accessibilityIdentifier("lab-takeaway")
            }
            if !result.footnote.isEmpty {
                Text(result.footnote).font(.system(size: 13)).foregroundStyle(AppTheme.secondary)
            }
            if !result.stopped.isEmpty {
                Text(result.stopped).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.amber)
            }
            ForEach(result.series.filter { !$0.ok && !$0.message.isEmpty }) { series in
                Text("\(series.name): \(series.message)").font(.system(size: 13)).foregroundStyle(AppTheme.coralInk)
            }
            Text("Timed on this device without the tracer. The shape suggests a growth rate; it does not prove Big O.")
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(12)
        .panelCard()
    }

    private var whatRan: String {
        let sizes = result.series.flatMap { $0.points.compactMap(\.first) }
        guard let low = sizes.min(), let high = sizes.max() else { return result.what }
        let format: (Double) -> String = { $0.formatted(.number.grouping(.automatic).precision(.fractionLength(0))) }
        let runs = result.runs > 3 ? "at least 3 times (up to \(result.runs) for fast sizes)" : "3 times"
        return "\(result.what) n goes from \(format(low)) to \(format(high)). Each size runs \(runs), and the chart shows the fastest run in milliseconds."
    }
}

/// The second button of every lab: runs the code on growing inputs, without the tracer.
struct LabScaleButton: View {
    let action: () -> Void

    var body: some View {
        LabActionButton(title: "How it scales", action: action)
            .accessibilityIdentifier("lab-scale")
    }
}
