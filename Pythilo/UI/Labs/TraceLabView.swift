import SwiftUI

/// Every lab built on the shared engine: write the code, trace it step by step, check it,
/// then see how it scales.
struct TraceLabView: View {
    let lab: LabInfo

    @State private var variantID = ""
    @State private var source = ""
    @State private var result: LabFrames?
    @State private var step = 0.0
    @State private var playing = false
    @State private var scale: LabScaleResult?
    @State private var traceIsStale = false
    @State private var showingAnswer = false
    @State private var confirmingReset = false
    @State private var bridge = EditorKeyboardBridge()
    private let session = RunSession.shared

    private var variant: LabVariant { lab.variants.first { $0.id == variantID } ?? lab.variants[0] }
    private var storageKey: String { "pythilo.lab.\(lab.id).\(variant.id)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if lab.variants.count > 1 {
                    LabChoice(options: lab.variants.map { ($0.id, $0.title) }, selection: $variantID)
                }
                Text(variant.prompt)
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabCodeBox(source: $source, filePath: variant.file, height: 230, bridge: bridge)
                HStack(spacing: 16) {
                    Button("Show the answer") { showingAnswer = true }
                        .accessibilityIdentifier("lab-answer")
                    Button("Start over") { confirmingReset = true }
                    Spacer()
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .buttonStyle(.app)
                HStack(spacing: 8) {
                    LabActionButton(title: "Trace", primary: true, action: runTrace).accessibilityIdentifier("lab-trace")
                    if variant.scales { LabScaleButton(action: runScale) }
                    if session.isBusy { LabActionButton(title: "Stop", action: session.stop) }
                }
                if let result, result.variant == variant.id { traceView(result) }
                if let scale, scale.variant == variant.id { LabScaleCard(result: scale) }
                Text(variant.scales
                     ? "Trace runs your code once, line by line, and draws what changed after each line. How it scales times it on bigger and bigger inputs."
                     : "Trace runs your code and draws every step of the learning loop around it.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                LabErrors()
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle(lab.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if variantID.isEmpty {
                variantID = UserDefaults.standard.string(forKey: "pythilo.lab.\(lab.id).variant") ?? lab.variants[0].id
                #if DEBUG
                if let chosen = UserDefaults.standard.string(forKey: "labVariant"), lab.variants.contains(where: { $0.id == chosen }) { variantID = chosen }
                #endif
                loadSource()
            }
            session.onCustom = { kind, data in
                if kind == "lab_frames", let value = try? JSONDecoder().decode(LabFrames.self, from: data) {
                    result = value
                    step = 0
                    playing = false
                    traceIsStale = false
                    #if DEBUG
                    let fraction = UserDefaults.standard.double(forKey: "labStep")
                    if fraction > 0 { step = Double(Int(Double(max(0, value.frames.count - 1)) * min(1, fraction))) }
                    #endif
                } else if kind == "lab_scale", let value = try? JSONDecoder().decode(LabScaleResult.self, from: data) {
                    scale = value
                }
            }
        }
        .onChange(of: variantID) { old, new in
            guard !old.isEmpty else { return }
            UserDefaults.standard.set(new, forKey: "pythilo.lab.\(lab.id).variant")
            playing = false
            loadSource()
        }
        .onChange(of: source) {
            UserDefaults.standard.set(source, forKey: storageKey)
            traceIsStale = result != nil
        }
        .task(id: playing) {
            while playing {
                try? await Task.sleep(for: .milliseconds(550))
                guard playing, let count = result?.frames.count else { break }
                if Int(step) >= count - 1 { playing = false } else { step += 1 }
            }
        }
        .sheet(isPresented: $showingAnswer) { answerSheet }
        .confirmationDialog("Put the starter code back?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { source = LabCatalog.code(lab.id, variant.id, .starter) }
        } message: {
            Text("Your code for this lab is replaced by the starter.")
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "labRun") {
                try? await Task.sleep(for: .seconds(1.5))
                runTrace()
                if UserDefaults.standard.bool(forKey: "labScale") {
                    while session.isBusy || result == nil { try? await Task.sleep(for: .milliseconds(200)) }
                    runScale()
                }
            }
        }
        #endif
    }

    private func loadSource() {
        let saved = UserDefaults.standard.string(forKey: storageKey)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "labAnswer") {
            source = LabCatalog.code(lab.id, variant.id, .answer)
            return
        }
        #endif
        source = saved ?? LabCatalog.code(lab.id, variant.id, .starter)
        traceIsStale = false
    }

    private func runTrace() {
        bridge.dismissKeyboard()
        session.clearOutput()
        playing = false
        session.submit(["kind": "lab_run", "lab": lab.id, "variant": variant.id, "source": source], label: "trace")
    }

    private func runScale() {
        bridge.dismissKeyboard()
        session.clearOutput()
        playing = false
        session.submit(["kind": "lab_scale", "lab": lab.id, "variant": variant.id, "source": source], label: "scale")
    }

    // MARK: The trace

    @ViewBuilder
    private func traceView(_ result: LabFrames) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if result.frames.isEmpty {
                Text("Nothing to show: the code stopped before its first step.")
                    .font(.system(size: 13.5)).foregroundStyle(AppTheme.secondary)
            } else {
                let index = min(Int(step), result.frames.count - 1)
                let frame = result.frames[index]
                if !frame.context.isEmpty {
                    Text(frame.context)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.secondary)
                        .lineLimit(2)
                }
                let columns = frame.panels.filter { $0.type == "array" }.map { ($0.cells?.count ?? 0) + ($0.offset ?? 0) }.max() ?? 0
                ForEach(Array(frame.panels.enumerated()), id: \.offset) { _, panel in
                    LabPanelView(panel: panel, columns: columns)
                }
                stepLine(frame)
                player(count: result.frames.count, index: index)
            }
            if traceIsStale {
                Text("You changed the code. This trace is from the earlier version. Trace again.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.amber)
            }
            if result.truncated {
                Text("Showing the first \(result.frames.count) steps; the run went on after that.")
                    .font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
            }
            checksView(result)
        }
        .padding(12)
        .panelCard()
    }

    private func stepLine(_ frame: LabFrame) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !frame.note.isEmpty {
                Text(frame.note)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lab-note")
            }
            if let line = frame.line, !frame.code.isEmpty {
                HStack(spacing: 8) {
                    Text("line \(line)").foregroundStyle(AppTheme.muted)
                    Text(frame.code).foregroundStyle(AppTheme.selectionInk).lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 12.5, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.selection.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func player(count: Int, index: Int) -> some View {
        VStack(spacing: 4) {
            if count > 1 {
                Slider(value: $step, in: 0...Double(count - 1), step: 1).tint(AppTheme.run)
                    .accessibilityIdentifier("lab-step")
            }
            HStack(spacing: 6) {
                playerButton("backward.end.fill", "First step") { playing = false; step = 0 }
                playerButton("chevron.left", "Previous step") { playing = false; step = max(0, step - 1) }
                playerButton(playing ? "pause.fill" : "play.fill", playing ? "Pause" : "Play") {
                    if !playing, index >= count - 1 { step = 0 }
                    playing.toggle()
                }
                playerButton("chevron.right", "Next step") { playing = false; step = min(Double(count - 1), step + 1) }
                playerButton("forward.end.fill", "Last step") { playing = false; step = Double(count - 1) }
                Spacer()
                Text("Step \(index + 1) of \(count)")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private func playerButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 40, height: 36)
                .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.app)
        .accessibilityLabel(label)
    }

    private func checksView(_ result: LabFrames) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabVerdict(correct: result.correct, success: "Every check passed", message: result.message.isEmpty ? "A check failed." : result.message)
            ForEach(result.checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.ok ? AppTheme.mint : AppTheme.coralInk)
                    Text(check.name).foregroundStyle(AppTheme.secondary)
                }
                .font(.system(size: 13.5))
            }
        }
    }

    private var answerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("One correct answer. Reading it is fine; tracing it and comparing with yours teaches more.")
                        .font(.system(size: 14)).foregroundStyle(AppTheme.secondary)
                    HighlightedCode(source: LabCatalog.code(lab.id, variant.id, .answer), path: variant.file)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.editor, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle("Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { showingAnswer = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use it") {
                        source = LabCatalog.code(lab.id, variant.id, .answer)
                        showingAnswer = false
                    }
                }
            }
        }
    }
}
