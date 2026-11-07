import SwiftUI

/// The strip that says what is running, where, and for how long.
struct RunStatusStrip: View {
    let session: RunSession
    let label: String

    private var state: (String, Color)? {
        switch session.phase {
        case .starting: ("Starting Python", AppTheme.muted)
        case .idle: nil
        case .running: ("Running", AppTheme.mint)
        case .waitingForInput: ("Waiting for input", AppTheme.amber)
        case .paused: ("Paused", AppTheme.blue)
        case .cancelling: ("Stopping", AppTheme.coralInk)
        case .unresponsive: ("Still running", AppTheme.coralInk)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if let state {
                Circle().fill(state.1).frame(width: 8, height: 8)
                Text(state.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(state.1)
            } else if let version = session.pythonVersion {
                Text("Python \(version)").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if !label.isEmpty { Text(label) ; Text("·") }
                Text("on this device")
                if session.isBusy, let started = session.runStartedAt {
                    Text("·")
                    Text(started, style: .timer)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(AppTheme.muted)
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

struct UnresponsiveBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This run cannot be stopped from here").font(.system(size: 16, weight: .bold))
            Text("Pythilo asked five times. The code is inside a compiled call or is ignoring the stop request.")
            Text("Your files are saved. To run anything else, close Pythilo from the app switcher and open it again.")
        }
        .font(.system(size: 14))
        .foregroundStyle(AppTheme.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.dangerPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppTheme.dangerBorder, lineWidth: 1) }
        .padding(10)
    }
}

struct ProblemsPanel: View {
    @Bindable var model: WorkspaceModel

    private var groups: [(String, [WorkspaceProblem])] {
        Dictionary(grouping: model.problems, by: \.path).sorted { $0.key < $1.key }
    }

    var body: some View {
        if model.problems.isEmpty {
            ContentUnavailableView("No problems", systemImage: "checkmark.circle", description: Text("Pythilo checks Python files as you type."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.0) { path, problems in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 7) {
                                FileIconView(name: (path as NSString).lastPathComponent)
                                Text(path).font(.system(size: 13, weight: .semibold, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Text("\(problems.count) \(problems.count == 1 ? "problem" : "problems")")
                                    .font(.system(size: 12)).foregroundStyle(AppTheme.muted)
                            }
                            .padding(.horizontal, 6)
                            ForEach(problems) { problem in
                                Button {
                                    model.open(problem.path, line: problem.line)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: problem.severity == "error" ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(problem.severity == "error" ? AppTheme.coral : AppTheme.amber)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(problem.message).font(.system(size: 14.5)).multilineTextAlignment(.leading)
                                            Text("Line \(problem.line) · \(problem.source)")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(AppTheme.muted)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(problem.severity == "error" ? AppTheme.dangerPanel : AppTheme.warnPanel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.app)
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
    }
}

struct OutputPanel: View {
    @Bindable var model: WorkspaceModel
    var showsStrip = true
    var fontSize: CGFloat = 14
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var session: RunSession { model.session }

    var body: some View {
        VStack(spacing: 0) {
            if showsStrip {
                RunStatusStrip(session: session, label: model.runLabel)
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }
            ZStack(alignment: .bottom) {
                if session.output.isEmpty, session.activeChannel == .output, !session.isBusy {
                    ContentUnavailableView("Nothing has run yet", systemImage: "play", description: Text("Run sends a file's output here."))
                }
                OutputTextView(chunks: session.output, revision: session.outputRevision, fontSize: fontSize)
                if session.phase == .unresponsive { UnresponsiveBanner() }
            }
            // After manage.py prints Django's commands, they are a tap away here too.
            if model.commands.framework != nil, !session.isBusy, !session.output.isEmpty {
                ProjectCommandBar(model: model)
            }
            if session.phase == .waitingForInput, session.activeChannel == .output {
                HStack(spacing: 8) {
                    Text("input()").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(AppTheme.amber)
                    TextField("", text: $input)
                        .font(.system(size: 14, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($inputFocused)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.run, lineWidth: 1) }
                        .accessibilityIdentifier("stdin-field")
                        .onSubmit(send)
                    Button { session.sendEndOfInput() } label: {
                        Text("EOF")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(height: 44)
                            .padding(.horizontal, 10)
                            .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.app)
                    .accessibilityLabel("Send end of input")
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(AppTheme.onRun)
                            .frame(width: 44, height: 44).background(AppTheme.run, in: Circle())
                    }
                    .buttonStyle(.app)
                    .accessibilityLabel("Send line")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.panel, ignoresSafeAreaEdges: [])
                .onAppear { inputFocused = true }
            }
        }
    }

    private func send() {
        session.sendInput(input)
        input = ""
    }
}

struct TerminalPanel: View {
    @Bindable var model: WorkspaceModel
    var fontSize: CGFloat = 13
    private var keyboard: TerminalKeyboardController { model.terminalKeyboard }

    private var session: RunSession { model.session }
    private var inProgram: Bool { session.isBusy && session.activeChannel == .terminal }
    /// A running server takes commands too: the model restarts it around them.
    private var acceptsInput: Bool { !session.isBusy || session.phase == .waitingForInput || session.listening != nil }

    private var placeholder: String {
        if session.phase == .waitingForInput { return "" }
        if session.listening != nil { return "Command (restarts the server)" }
        return session.isBusy ? "Running. Ctrl-C stops it" : ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if session.terminalOutput.isEmpty {
                    VStack(spacing: 6) {
                        Text("Type a command. Try help.").foregroundStyle(AppTheme.muted)
                    }
                    .font(.system(size: 14))
                }
                OutputTextView(chunks: session.terminalOutput, revision: session.terminalRevision, fontSize: fontSize)
            }
            .frame(maxHeight: .infinity)
            if !model.commands.featured.isEmpty || !model.commands.npm.isEmpty { ProjectCommandBar(model: model) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["python", "pip", "npm", "pytest", "git", "ls"], id: \.self) { word in
                        key(word) { insert(word + " ") }
                    }
                    key("Ctrl-C") { session.stop() }
                    key("↑") { recall() }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 52)
            .background(AppTheme.panel, ignoresSafeAreaEdges: [])
            HStack(spacing: 8) {
                Text(session.phase == .waitingForInput ? ">" : "$")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppTheme.blue)
                TerminalPrompt(text: $model.terminalInput, placeholder: placeholder, keyboard: keyboard,
                    onSubmit: submit, onPrevious: recall, onNext: recallNext, onStop: { session.stop() })
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .background(AppTheme.panel, ignoresSafeAreaEdges: [])
        }
        .onChange(of: model.terminalDraft, initial: true) { _, draft in
            guard let draft else { return }
            model.terminalInput = draft
            model.terminalDraft = nil
            keyboard.focus()
        }
    }

    private func key(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.app)
    }

    private func insert(_ text: String) {
        keyboard.insert(text)
    }

    private func recall() {
        guard !model.terminalHistory.isEmpty else { return }
        let next = max(0, (model.terminalHistoryIndex ?? model.terminalHistory.count) - 1)
        model.terminalHistoryIndex = next
        model.terminalInput = model.terminalHistory[next]
        keyboard.focus()
    }

    private func recallNext() {
        guard let historyIndex = model.terminalHistoryIndex else { return }
        let next = historyIndex + 1
        model.terminalHistoryIndex = next < model.terminalHistory.count ? next : nil
        model.terminalInput = next < model.terminalHistory.count ? model.terminalHistory[next] : ""
        keyboard.focus()
    }

    private func submit() {
        // The field stays editable while a program runs: disabling it would drop
        // the keyboard and bring it back each time a server restarts. A line
        // typed meanwhile waits in the field until Enter can run it.
        guard acceptsInput else {
            keyboard.focus()
            return
        }
        let text = model.terminalInput
        model.terminalInput = ""
        model.terminalHistoryIndex = nil
        keyboard.focus()
        if session.phase == .waitingForInput, session.activeChannel == .terminal {
            session.noteTerminal(text + "\n", kind: .input)
            session.sendInput(text)
            return
        }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { model.terminalHistory.append(text) }
        model.runTerminal(text)
    }
}

struct DebugPanel: View {
    @Bindable var model: WorkspaceModel
    @State private var expression = ""
    @State private var frameIndex = 0

    private var session: RunSession { model.session }

    var body: some View {
        if let pause = session.debugPause {
            paused(pause)
        } else {
            idle
        }
    }

    private var idle: some View {
        VStack(spacing: 12) {
            if session.isBusy {
                Text("Running until a breakpoint").font(.system(size: 16, weight: .semibold))
                Text("Execution continues in the program. Stop ends it.").font(.system(size: 14)).foregroundStyle(AppTheme.muted)
            } else {
                Image(systemName: "ladybug").font(.system(size: 30)).foregroundStyle(AppTheme.muted)
                Text("Tap a line number to set a breakpoint").font(.system(size: 16, weight: .semibold))
                let count = model.breakpoints.values.reduce(0) { $0 + $1.count }
                Text(count == 0 ? "Without one, it stops on the first line." : "\(count) set")
                    .font(.system(size: 14)).foregroundStyle(AppTheme.muted)
                Button {
                    model.debugSelected()
                } label: {
                    Label("Debug \(model.selectedPath ?? "file")", systemImage: "ladybug.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.onRun)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(AppTheme.run, in: Capsule())
                }
                .buttonStyle(.app)
                .disabled(session.phase != .idle)
                .accessibilityIdentifier("debug-start")
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func excerpt(_ pause: DebugPause) -> some View {
        let root = model.project.url.resolvingSymlinksInPath().path + "/"
        let relative = pause.file.hasPrefix(root) ? String(pause.file.dropFirst(root.count)) : pause.file
        let lines = (model.buffers[relative] ?? (try? String(contentsOfFile: pause.file, encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
        let first = max(1, pause.line - 3)
        let last = min(lines.count, pause.line + 3)
        return VStack(alignment: .leading, spacing: 0) {
            if first <= last {
                ForEach(first...last, id: \.self) { number in
                    HStack(spacing: 0) {
                        Text("\(number)")
                            .foregroundStyle(number == pause.line ? AppTheme.primary : AppTheme.muted)
                            .frame(width: 30, alignment: .trailing)
                            .padding(.trailing, 8)
                        Text(lines[number - 1]).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22)
                    .background(number == pause.line ? AppTheme.selection : Color.clear)
                    .overlay(alignment: .leading) {
                        if number == pause.line { Rectangle().fill(AppTheme.blue).frame(width: 3) }
                    }
                }
            }
        }
        .font(.system(size: 13.5, design: .monospaced))
        .padding(.vertical, 5)
        .background(AppTheme.rail, ignoresSafeAreaEdges: [])
        .onTapGesture { model.open(relative, line: pause.line) }
    }

    private func control(_ title: String, _ symbol: String, primary: Bool = false, command: String) -> some View {
        Button {
            session.debug(command)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(primary ? AppTheme.onRun : AppTheme.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(primary ? AppTheme.run : AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.app)
    }

    private func paused(_ pause: DebugPause) -> some View {
        VStack(spacing: 0) {
            excerpt(pause)
            HStack(spacing: 6) {
                control("Continue", "play.fill", primary: true, command: "continue")
                control("Step over", "arrow.uturn.right", command: "next")
                control("Step in", "arrow.down.to.line", command: "step")
                control("Step out", "arrow.up.to.line", command: "return")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.panel, ignoresSafeAreaEdges: [])
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CALL STACK").sectionLabel()
                            Spacer()
                            // Other threads keep running while this one is paused.
                            if let thread = pause.thread, thread != "MainThread" {
                                Text(thread).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(AppTheme.selectionInk)
                            }
                        }
                        .padding(.horizontal, 4)
                        ForEach(Array(pause.frames.enumerated()), id: \.offset) { index, frame in
                            Button {
                                frameIndex = index
                            } label: {
                                HStack {
                                    Text(frame.name)
                                    Spacer()
                                    Text("\((frame.file as NSString).lastPathComponent):\(frame.line)").foregroundStyle(AppTheme.muted)
                                }
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 10)
                                .frame(height: 44)
                                .background(index == min(frameIndex, pause.frames.count - 1) ? AppTheme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.app)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("VARIABLES").sectionLabel().padding(.leading, 4)
                        let frame = pause.frames.indices.contains(frameIndex) ? pause.frames[frameIndex] : pause.frames.first
                        ForEach(frame?.locals ?? []) { variable in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(variable.name)
                                Text(variable.value).foregroundStyle(AppTheme.mint).lineLimit(2)
                                Spacer(minLength: 4)
                                Text(variable.type).foregroundStyle(AppTheme.muted)
                            }
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 10)
                        }
                        if frame?.locals.isEmpty != false {
                            Text("No local variables").font(.system(size: 13)).foregroundStyle(AppTheme.muted).padding(.horizontal, 10)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("EVAL").sectionLabel()
                        TextField("expression", text: $expression)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border, lineWidth: 1) }
                            .onSubmit {
                                session.evaluate(expression)
                            }
                        if let result = session.debugEvaluations.last {
                            Text(result.value ?? result.error ?? "")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(result.error == nil ? AppTheme.amber : AppTheme.coralInk)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
            }
        }
        .onChange(of: pause.line) { frameIndex = 0 }
    }
}
