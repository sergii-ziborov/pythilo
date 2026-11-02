import SwiftUI

struct LearnView: View {
    let onOpenProject: (Project) -> Void
    @State private var library = CourseLibrary.shared
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if library.courses.isEmpty {
                        ContentUnavailableView("Courses are missing from this build", systemImage: "book.closed")
                    }
                    if let (course, lesson) = library.lastLesson {
                        NavigationLink(value: LessonRoute(course: course, lesson: lesson)) {
                            continueCard(course, lesson)
                        }
                        .buttonStyle(.plain)
                    }
                    if let interview = library.interview {
                        NavigationLink(value: interview) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Interview practice").font(.system(size: 15.5, weight: .semibold))
                                    Text("\(library.completedCount(interview)) of \(interview.lessons.count) solved · timed, with real tests")
                                        .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
                            }
                            .padding(14)
                            .panelCard()
                        }
                        .buttonStyle(.plain)
                    }
                    Text("PATH").sectionLabel().padding(.top, 6)
                    VStack(spacing: 2) {
                        ForEach(Array(library.paths.enumerated()), id: \.element.id) { index, course in
                            NavigationLink(value: course) { courseRow(course, number: index + 1) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Learn")
            .navigationDestination(for: Course.self) { CourseView(course: $0) }
            .navigationDestination(for: LessonRoute.self) { route in
                LessonView(course: route.course, lesson: route.lesson, onOpenProject: onOpenProject)
            }
        }
    }

    private func continueCard(_ course: Course, _ lesson: Lesson) -> some View {
        let done = library.completedCount(course)
        return VStack(alignment: .leading, spacing: 6) {
            Text("CONTINUE").font(.system(size: 12, weight: .bold)).kerning(0.7).foregroundStyle(AppTheme.selectionInk)
            Text(lesson.title).font(.system(size: 19, weight: .bold)).multilineTextAlignment(.leading)
            Text("\(course.title) · \(done) of \(course.lessons.count) done").font(.system(size: 14)).foregroundStyle(AppTheme.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.background)
                    Capsule().fill(AppTheme.blue).frame(width: geometry.size.width * CGFloat(done) / CGFloat(max(1, course.lessons.count)))
                }
            }
            .frame(height: 6)
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.selection, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func courseRow(_ course: Course, number: Int) -> some View {
        let done = library.completedCount(course)
        let finished = done == course.lessons.count && done > 0
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(finished ? AppTheme.mint.opacity(0.2) : done > 0 ? AppTheme.selection : AppTheme.raised)
                if finished {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(AppTheme.mint)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .heavy)).foregroundStyle(done > 0 ? AppTheme.selectionInk : AppTheme.secondary)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(course.title).font(.system(size: 15.5, weight: .semibold))
                Text("\(course.lessons.count) lessons\(done > 0 ? " · \(done) done" : "") · \(course.summary)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityIdentifier("course-\(course.id)")
    }
}

struct LessonRoute: Hashable {
    let course: Course
    let lesson: Lesson
}

struct CourseView: View {
    let course: Course
    @State private var library = CourseLibrary.shared

    var body: some View {
        List(course.lessons) { lesson in
            NavigationLink(value: LessonRoute(course: course, lesson: lesson)) {
                HStack(spacing: 10) {
                    Image(systemName: library.completed.contains(lesson.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(library.completed.contains(lesson.id) ? AppTheme.mint : AppTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.title).font(.system(size: 15.5, weight: .medium))
                        if let level = lesson.level {
                            Text("\(level) · \(lesson.minutes ?? 25) min").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
        }
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A lesson or an interview task: the explanation, your code, real checks.
struct LessonView: View {
    let course: Course
    let lesson: Lesson
    let onOpenProject: (Project) -> Void
    @State private var code = ""
    @State private var cursor = 0
    @State private var results: [CheckResult] = []
    @State private var runID: String?
    @State private var hintsShown = 0
    @State private var showSolution = false
    @State private var library = CourseLibrary.shared
    @State private var failure: String?
    @State private var started = Date()
    @State private var bridge = EditorKeyboardBridge()
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let session = RunSession.shared
    private var isInterview: Bool { course.kind == "interview" }
    private var passed: Int { results.filter(\.ok).count }
    private var allPassed: Bool { !results.isEmpty && passed == results.count }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    ScrollView { brief.padding(16) }.frame(maxWidth: .infinity)
                    Rectangle().fill(AppTheme.border).frame(width: 1)
                    workspace.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView { brief.padding(16) }.frame(maxHeight: .infinity)
                    Rectangle().fill(AppTheme.border).frame(height: 1)
                    workspace.frame(maxHeight: .infinity)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(isInterview ? (lesson.level ?? "Interview") : course.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if session.isBusy {
                    Button("Stop", systemImage: "stop.fill") { session.stop() }.tint(AppTheme.coral)
                } else {
                    Button(action: check) {
                        Label(isInterview ? "Test" : "Check", systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.run)
                    .foregroundStyle(AppTheme.onRun)
                    .accessibilityIdentifier("lesson-check")
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: saveDraft)
        .onChange(of: code) { saveDraft() }
    }

    private var brief: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isInterview {
                HStack {
                    Text(lesson.level ?? "").font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    Spacer()
                    Text(timerInterval: started...started.addingTimeInterval(TimeInterval((lesson.minutes ?? 25) * 60)), countsDown: true)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.amber)
                        .frame(width: 80, alignment: .trailing)
                }
            }
            Text(lesson.title).font(.system(size: 24, weight: .bold))
            MarkdownBlocks(markdown: lesson.body)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your turn").font(.system(size: 14.5, weight: .bold))
                Text(lesson.task).font(.system(size: 14.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.selection, in: RoundedRectangle(cornerRadius: 10))
            if hintsShown > 0 {
                ForEach(Array(lesson.hints.prefix(hintsShown).enumerated()), id: \.offset) { index, hint in
                    Text("Hint \(index + 1). \(hint)")
                        .font(.system(size: 14))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.warnPanel, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if allPassed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why this works").font(.system(size: 14.5, weight: .bold))
                    MarkdownBlocks(markdown: lesson.explanation)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                FileIconView(name: "solution.py")
                Text("solution.py").font(.system(size: 13, design: .monospaced))
                Spacer()
                if hintsShown < lesson.hints.count {
                    Button("Hint \(hintsShown + 1) of \(lesson.hints.count)") { hintsShown += 1 }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                } else if !showSolution {
                    Button("Show solution") { showSolution = true; code = lesson.solution }
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(AppTheme.rail)
            SyntaxCodeEditor(
                text: $code,
                cursorOffset: $cursor,
                filePath: "solution.py",
                isEditable: !session.isBusy,
                tracksTyping: false,
                navigationTarget: nil,
                keyboardBridge: bridge,
                onRequestCompletion: {}
            )
            if !results.isEmpty { report }
        }
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(allPassed ? "All \(results.count) checks passed" : "\(passed) of \(results.count) checks passed")
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(allPassed ? AppTheme.mint : AppTheme.primary)
            ForEach(results) { result in
                if !result.ok {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.name).font(.system(size: 13, weight: .semibold))
                        Text(result.message).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(AppTheme.coralInk).lineLimit(3)
                    }
                }
            }
            if !allPassed {
                Button("Debug in a project", action: keepAsProject)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
            } else {
                Button("Keep as a project", action: keepAsProject)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
            }
            if let failure { Text(failure).font(.system(size: 13)).foregroundStyle(AppTheme.coralInk) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(allPassed ? AppTheme.panel : AppTheme.dangerPanel)
        .accessibilityIdentifier("lesson-report")
    }

    private func load() {
        library.markOpened(lesson)
        let draft = CourseLibrary.draftURL(lesson)
        code = (try? String(contentsOf: draft, encoding: .utf8)) ?? lesson.starter
        session.onCustom = nil
    }

    private func saveDraft() {
        guard !code.isEmpty else { return }
        try? code.write(to: CourseLibrary.draftURL(lesson), atomically: true, encoding: .utf8)
    }

    private func check() {
        saveDraft()
        bridge.dismissKeyboard()
        results = []
        let url = CourseLibrary.draftURL(lesson)
        session.onCustom = { [lesson] kind, data in
            guard kind == "lesson_result", let report = try? JSONDecoder().decode(LessonReport.self, from: data) else { return }
            results = report.results
            if !report.results.isEmpty, report.results.allSatisfy(\.ok) {
                CourseLibrary.shared.markCompleted(lesson)
            }
        }
        runID = session.submit(
            [
                "kind": "lesson_check",
                "path": url.path,
                "root": url.deletingLastPathComponent().path,
                "cwd": url.deletingLastPathComponent().path,
                "checks": lesson.checks.map { ["name": $0.name, "code": $0.code] },
            ],
            label: lesson.title
        )
    }

    private func keepAsProject() {
        let tests = lesson.checks.enumerated().map { index, check in
            let body = check.code.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
            return "def test_\(index + 1)():\n    # \(check.name)\n\(body)\n"
        }.joined(separator: "\n\n")
        let template = ProjectTemplate(
            id: "lesson",
            title: lesson.title,
            summary: "",
            systemImage: "book",
            files: [
                "solution.py": code,
                "test_solution.py": "from solution import *\n\n_stdout = \"\"\n\n\n\(tests)",
                "README.md": "# \(lesson.title)\n\n\(lesson.task)\n\nRun `pytest` in the Terminal.\n",
                ".gitignore": ".pythilo/\n__pycache__/\n",
            ]
        )
        do {
            onOpenProject(try ProjectStore.shared.create(name: lesson.id, template: template))
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Markdown with code blocks in the editor's colours.
struct MarkdownBlocks: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownRenderer.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .code(source):
                    HighlightedCode(source: source)
                        .padding(10)
                        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 10))
                case .blank:
                    EmptyView()
                default:
                    Text(MarkdownRenderer.attributed(Self.text(block)))
                        .font(.system(size: 15.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func text(_ block: MarkdownRenderer.Block) -> String {
        switch block {
        case let .heading(level, text): String(repeating: "#", count: level) + " " + text
        case let .bullet(text): "- " + text
        case let .paragraph(text): text
        default: ""
        }
    }
}
