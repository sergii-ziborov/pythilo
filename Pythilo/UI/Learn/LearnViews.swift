import SwiftUI

/// Courses grouped the way people choose them. Order inside a track is the order to take them.
enum LearnTrack: String, CaseIterable, Identifiable {
    case python, web, ml, ai, projects, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .python: "Python"
        case .web: "Web, data & APIs"
        case .ml: "Machine learning"
        case .ai: "AI & transformers"
        case .projects: "Algorithms & projects"
        case .more: "More"
        }
    }

    var shortTitle: String {
        switch self {
        case .python: "Python"
        case .web: "Web & data"
        case .ml: "ML"
        case .ai: "AI"
        case .projects: "Projects"
        case .more: "More"
        }
    }

    var systemImage: String {
        switch self {
        case .python: "chevron.left.forwardslash.chevron.right"
        case .web: "globe"
        case .ml: "brain"
        case .ai: "sparkles"
        case .projects: "puzzlepiece.extension"
        case .more: "ellipsis.circle"
        }
    }

    var tint: Color {
        switch self {
        case .python: AppTheme.blue
        case .web: AppTheme.mint
        case .ml: AppTheme.violet
        case .ai: AppTheme.coral
        case .projects: AppTheme.amber
        case .more: AppTheme.secondary
        }
    }

    private static let courses: [LearnTrack: [String]] = [
        .python: ["foundations", "deeper", "clean-code", "testing", "tools", "architecture", "async", "python-runtime", "python-systems"],
        .web: ["web", "data", "pydantic", "fastapi-httpx", "data-formats", "data-practice", "testing-practice", "reliable-python"],
        .ml: ["math", "ml", "ml-practice", "ml-evaluation", "ml-statistics", "ml-production", "ml-systems", "deep-learning-practice", "pytorch-training", "robust-ml-engineering"],
        .ai: ["llm", "ai", "ai-building-blocks", "ai-production", "ai-systems", "transformer-engineering", "finetuning-projects", "alignment-engineering"],
        .projects: ["algorithm-patterns", "senior-projects"],
    ]

    static func track(of course: Course) -> LearnTrack {
        courses.first { $0.value.contains(course.id) }?.key ?? .more
    }

    func courses(in paths: [Course]) -> [Course] {
        guard let ids = Self.courses[self] else {
            return paths.filter { Self.track(of: $0) == .more }
        }
        return ids.compactMap { id in paths.first { $0.id == id } }
    }
}

struct LearnView: View {
    let onOpenProject: (Project) -> Void
    @State private var library = CourseLibrary.shared
    @State private var path = NavigationPath()
    @State private var track: LearnTrack?
    @State private var query = ""

    private var tracks: [LearnTrack] {
        LearnTrack.allCases.filter { !$0.courses(in: library.paths).isEmpty }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if library.courses.isEmpty {
                        ContentUnavailableView("Courses are missing from this build", systemImage: "book.closed")
                    }
                    if !query.isEmpty {
                        searchResults
                    } else {
                        if let (course, lesson) = library.nextLesson {
                            NavigationLink(value: LessonRoute(course: course, lesson: lesson)) {
                                ContinueCard(course: course, lesson: lesson)
                            }
                            .buttonStyle(.app)
                            .accessibilityIdentifier("learn-continue")
                        }
                        ProgressStrip()
                        if let interview = library.interview {
                            NavigationLink(value: interview) { PracticeCard(course: interview) }
                                .buttonStyle(.app)
                                .accessibilityIdentifier("learn-practice")
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COURSES").sectionLabel()
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    trackChip(nil)
                                    ForEach(tracks) { trackChip($0) }
                                }
                                .padding(.vertical, 2)
                            }
                            .scrollClipDisabled()
                        }
                        ForEach(track.map { [$0] } ?? tracks) { item in
                            trackSection(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Learn")
            .toolbar { DownloadsLink() }
            .searchable(text: $query, prompt: "Search lessons and courses")
            .navigationDestination(for: Course.self) { CourseView(course: $0) }
            .navigationDestination(for: String.self) { id in
                LabDestination(id: id)
            }
            .navigationDestination(for: LessonRoute.self) { route in
                LessonView(course: route.course, lesson: route.lesson, onOpenProject: onOpenProject) { next in
                    path.removeLast()
                    path.append(LessonRoute(course: route.course, lesson: next))
                }
            }
            #if DEBUG
            .task(openFromLaunchArguments)
            #endif
        }
    }

    private func trackChip(_ item: LearnTrack?) -> some View {
        let active = track == item
        let tint = item?.tint ?? AppTheme.blue
        let count = item.map { $0.courses(in: library.paths).count } ?? library.paths.count
        let title = "\(item?.shortTitle ?? "All") · \(count)"
        return Button { withAnimation(.snappy(duration: 0.2)) { track = item } } label: {
            HStack(spacing: 6) {
                Image(systemName: item?.systemImage ?? "square.grid.2x2").font(.system(size: 11.5, weight: .bold))
                Text(title).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(active ? AppTheme.onBlue : AppTheme.secondary)
            .background(active ? tint : AppTheme.panel, in: Capsule())
            .overlay { if !active { Capsule().stroke(AppTheme.border, lineWidth: 1) } }
        }
        .buttonStyle(.app)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("learn-track-\(item?.rawValue ?? "all")")
    }

    private func trackSection(_ item: LearnTrack) -> some View {
        let courses = item.courses(in: library.paths)
        let lessons = courses.reduce(0) { $0 + $1.lessons.count }
        let done = courses.reduce(0) { $0 + library.completedCount($1) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(item.tint)
                    .frame(width: 30, height: 30)
                    .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 19, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(courses.count) courses · \(lessons) lessons\(done > 0 ? " · \(done) done" : "")")
                        .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                    NavigationLink(value: course) {
                        PathRow(course: course, number: index + 1, isLast: index == courses.count - 1, tint: item.tint)
                    }
                    .buttonStyle(.app)
                }
            }
            .padding(14)
            .panelCard(cornerRadius: 18)
        }
        .padding(.top, 4)
    }

    /// Lessons and courses whose titles match, across the whole library.
    @ViewBuilder
    private var searchResults: some View {
        let courses = library.courses.filter { "\($0.title) \($0.summary)".localizedCaseInsensitiveContains(query) }
        let lessons = library.courses.flatMap { course in
            course.lessons.filter { $0.title.localizedCaseInsensitiveContains(query) }.map { (course, $0) }
        }
        if courses.isEmpty && lessons.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        if !courses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("COURSES · \(courses.count)").sectionLabel()
                ForEach(courses) { course in
                    NavigationLink(value: course) {
                        SearchRow(title: course.title, detail: "\(course.lessons.count) \(course.kind == "interview" ? "tasks" : "lessons")",
                                  systemImage: course.kind == "interview" ? "stopwatch" : LearnTrack.track(of: course).systemImage,
                                  tint: course.kind == "interview" ? AppTheme.violet : LearnTrack.track(of: course).tint)
                    }
                    .buttonStyle(.app)
                }
            }
        }
        if !lessons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("LESSONS · \(lessons.count)").sectionLabel()
                ForEach(lessons.prefix(60), id: \.1.id) { course, lesson in
                    NavigationLink(value: LessonRoute(course: course, lesson: lesson)) {
                        SearchRow(title: lesson.title, detail: course.title,
                                  systemImage: library.completed.contains(lesson.id) ? "checkmark.circle.fill" : "book",
                                  tint: library.completed.contains(lesson.id) ? AppTheme.mint : AppTheme.blue)
                    }
                    .buttonStyle(.app)
                    .accessibilityIdentifier("search-lesson-\(lesson.id)")
                }
                if lessons.count > 60 {
                    Text("Showing 60 of \(lessons.count). Type more to narrow it down.")
                        .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                }
            }
        }
    }

    #if DEBUG
    /// For screenshots: -openCourse foundations, -openLesson values-and-names.
    private func openFromLaunchArguments() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "openCourse"), let course = library.courses.first(where: { $0.id == id }) {
            path.append(course)
        }
        if let id = defaults.string(forKey: "openLesson") {
            for course in library.courses {
                if let lesson = course.lessons.first(where: { $0.id == id }) { path.append(LessonRoute(course: course, lesson: lesson)) }
            }
        }
    }
    #endif
}

private struct SearchRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(AppTheme.primary)
                    .multilineTextAlignment(.leading)
                Text(detail).font(.system(size: 13)).foregroundStyle(AppTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
        }
        .padding(12)
        .panelCard(cornerRadius: 14)
        .contentShape(Rectangle())
    }
}

/// How far along you are, across every course.
private struct ProgressStrip: View {
    @State private var library = CourseLibrary.shared

    var body: some View {
        let paths = library.paths
        let lessons = paths.reduce(0) { $0 + $1.lessons.count }
        let done = paths.reduce(0) { $0 + library.completedCount($1) }
        let finished = paths.filter { !$0.lessons.isEmpty && library.completedCount($0) == $0.lessons.count }.count
        let solved = library.interview.map { library.completedCount($0) } ?? 0
        let tasks = library.interview?.lessons.count ?? 0
        HStack(spacing: 8) {
            fact("\(done)", "of \(lessons) lessons", systemImage: "book.fill", tint: AppTheme.blue)
            fact("\(finished)", "of \(paths.count) courses", systemImage: "flag.checkered", tint: AppTheme.mint)
            if tasks > 0 { fact("\(solved)", "of \(tasks) tasks", systemImage: "stopwatch.fill", tint: AppTheme.violet) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("learn-progress")
    }

    private func fact(_ value: String, _ label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text(label).font(.system(size: 12)).foregroundStyle(AppTheme.muted).lineLimit(1).minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(cornerRadius: 14)
    }
}

struct LessonRoute: Hashable {
    let course: Course
    let lesson: Lesson
}

extension CourseLibrary {
    /// Where to pick up: the lesson you left unfinished, or the one after it.
    var nextLesson: (Course, Lesson)? {
        if let (course, lesson) = lastLesson {
            if !completed.contains(lesson.id) { return (course, lesson) }
            if let next = course.lessons.first(where: { !completed.contains($0.id) }) { return (course, next) }
        }
        for course in paths {
            if let next = course.lessons.first(where: { !completed.contains($0.id) }) { return (course, next) }
        }
        return nil
    }

    func next(after lesson: Lesson, in course: Course) -> Lesson? {
        guard let index = course.lessons.firstIndex(of: lesson), index + 1 < course.lessons.count else { return nil }
        return course.lessons[index + 1]
    }

    func minutes(_ course: Course) -> Int {
        course.lessons.reduce(0) { $0 + ($1.minutes ?? 25) }
    }
}

/// "3 h 20 min" rather than "200 min".
private func duration(_ minutes: Int) -> String {
    minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
}

private struct ProgressBar: View {
    let value: Double
    var tint: Color = AppTheme.blue
    var track: Color = AppTheme.raised

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(value > 0 ? 6 : 0, geometry.size.width * min(1, value)))
            }
        }
        .frame(height: 6)
    }
}

private struct ProgressRing: View {
    let value: Double
    var size: CGFloat = 36
    var tint: Color = AppTheme.blue

    var body: some View {
        ZStack {
            Circle().stroke(AppTheme.raised, lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, value))
                .stroke(value >= 1 ? AppTheme.mint : tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct ContinueCard: View {
    let course: Course
    let lesson: Lesson
    @State private var library = CourseLibrary.shared

    var body: some View {
        let done = library.completedCount(course)
        let index = (course.lessons.firstIndex(of: lesson) ?? 0) + 1
        let started = library.lastLessonID != nil
        VStack(alignment: .leading, spacing: 0) {
            Text(started ? "CONTINUE" : "START HERE")
                .font(.system(size: 12, weight: .bold)).kerning(0.7)
                .foregroundStyle(AppTheme.selectionInk)
            Text(lesson.title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.leading)
                .padding(.top, 6)
            Text("\(course.title) · lesson \(index) of \(course.lessons.count) · \(lesson.minutes ?? 25) min")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.secondary)
                .padding(.top, 4)
            HStack(spacing: 12) {
                ProgressBar(value: Double(done) / Double(max(1, course.lessons.count)), track: AppTheme.panel)
                Text("\(done)/\(course.lessons.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.selectionInk)
            }
            .padding(.top, 16)
            HStack(spacing: 6) {
                Text(started ? "Continue lesson" : "Start lesson")
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(AppTheme.onBlue)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 16)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.selection, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One course on the path: a node on a line, with its progress.
private struct PathRow: View {
    let course: Course
    let number: Int
    let isLast: Bool
    var tint: Color = AppTheme.blue
    @State private var library = CourseLibrary.shared

    var body: some View {
        let done = library.completedCount(course)
        let total = course.lessons.count
        let finished = done == total && total > 0
        let current = !finished && (done > 0 || library.nextLesson?.0.id == course.id)
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    ProgressRing(value: Double(done) / Double(max(1, total)), size: 38, tint: tint)
                    if finished {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(AppTheme.mint)
                    } else {
                        Text("\(number)").font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(current ? tint : AppTheme.secondary)
                    }
                }
                if !isLast {
                    Rectangle().fill(finished ? AppTheme.mint.opacity(0.5) : AppTheme.border).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(course.title).font(.system(size: 16.5, weight: .semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.muted)
                }
                Text(course.summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AppTheme.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if current, !finished {
                        Text(done > 0 ? "In progress" : "Up next")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(AppTheme.onBlue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tint, in: Capsule())
                    }
                    Text(finished ? "Done · \(total) lessons" : "\(total) lessons · \(duration(library.minutes(course)))\(done > 0 ? " · \(done) done" : "")")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(finished ? AppTheme.mint : current ? tint : AppTheme.muted)
                }
                .padding(.top, 1)
            }
            .padding(.top, 1)
            .padding(.bottom, isLast ? 0 : 18)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("course-\(course.id)")
    }
}

private struct PracticeCard: View {
    let course: Course
    @State private var library = CourseLibrary.shared

    var body: some View {
        let done = library.completedCount(course)
        let levels = ["Easy", "Medium", "Hard"].map { level in (level, course.lessons.filter { $0.level == level }.count) }.filter { $0.1 > 0 }
        HStack(spacing: 14) {
            Image(systemName: "stopwatch")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppTheme.violet)
                .frame(width: 46, height: 46)
                .background(AppTheme.violet.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(.system(size: 16.5, weight: .semibold))
                Text("\(done) of \(course.lessons.count) solved · timed, with real tests")
                    .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                if !levels.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(levels, id: \.0) { level, count in
                            Text("\(count) \(level.lowercased())")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(level == "Easy" ? AppTheme.mint : level == "Medium" ? AppTheme.amber : AppTheme.coralInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background((level == "Easy" ? AppTheme.mint : level == "Medium" ? AppTheme.amber : AppTheme.coral).opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.muted)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.violet.opacity(0.10), AppTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.violet.opacity(0.2), lineWidth: 1) }
    }
}

// MARK: - Course

struct CourseView: View {
    let course: Course
    @State private var library = CourseLibrary.shared

    private var isInterview: Bool { course.kind == "interview" }

    var body: some View {
        let course = library.courses.first(where: { $0.id == self.course.id }) ?? self.course
        let done = library.completedCount(course)
        let next = course.lessons.first { !library.completed.contains($0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ContentDownloadCard(packID: "course-\(course.id)").padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(course.summary)
                        .font(.system(size: 15.5))
                        .foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        stat("\(course.lessons.count)", isInterview ? "tasks" : "lessons")
                        stat(duration(library.minutes(course)), "in total")
                        stat("\(done)", isInterview ? "solved" : "done")
                    }
                    .padding(.top, 16)
                    ProgressBar(value: Double(done) / Double(max(1, course.lessons.count)), tint: done == course.lessons.count ? AppTheme.mint : AppTheme.blue)
                        .padding(.top, 14)
                    if let next {
                        NavigationLink(value: LessonRoute(course: course, lesson: next)) {
                            HStack(spacing: 6) {
                                Text(done == 0 ? "Start: \(next.title)" : "Continue: \(next.title)").lineLimit(1)
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.onBlue)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.app)
                        .padding(.top, 16)
                    }
                }
                .padding(18)
                .panelCard(cornerRadius: 20)

                Text(isInterview ? "TASKS" : "LESSONS").sectionLabel().padding(.top, 26).padding(.bottom, 10)
                VStack(spacing: 0) {
                    ForEach(Array(course.lessons.enumerated()), id: \.element.id) { index, lesson in
                        NavigationLink(value: LessonRoute(course: course, lesson: lesson)) {
                            LessonRow(
                                lesson: lesson,
                                number: index + 1,
                                state: library.completed.contains(lesson.id) ? .done : lesson.id == next?.id ? .current : .upcoming,
                                isInterview: isInterview,
                                isLast: index == course.lessons.count - 1
                            )
                        }
                        .buttonStyle(.app)
                        .accessibilityIdentifier("lesson-\(lesson.id)")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.background)
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 12.5)).foregroundStyle(AppTheme.muted)
        }
    }
}

private struct LessonRow: View {
    enum State { case done, current, upcoming }

    let lesson: Lesson
    let number: Int
    let state: State
    let isInterview: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    switch state {
                    case .done:
                        Circle().fill(AppTheme.mint)
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(AppTheme.panel)
                    case .current:
                        Circle().fill(AppTheme.blue)
                        Text("\(number)").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(AppTheme.onBlue)
                    case .upcoming:
                        Circle().stroke(AppTheme.border, lineWidth: 2)
                        Text("\(number)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.muted)
                    }
                }
                .frame(width: 32, height: 32)
                .padding(.top, state == .current ? 14 : 10)
                if !isLast {
                    Rectangle().fill(state == .done ? AppTheme.mint.opacity(0.5) : AppTheme.border).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title)
                    .font(.system(size: 16.5, weight: state == .current ? .bold : .semibold))
                    .foregroundStyle(state == .upcoming ? AppTheme.secondary : AppTheme.primary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ForEach(details, id: \.self) { detail in
                        Text(detail)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AppTheme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppTheme.raised, in: Capsule())
                    }
                }
                if state == .current {
                    Text("Up next")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.selectionInk)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(state == .current ? 14 : 10)
            .background {
                if state == .current {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppTheme.selection)
                }
            }
            .padding(.bottom, isLast ? 0 : 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
                .padding(.top, state == .current ? 22 : 18)
        }
        .contentShape(Rectangle())
    }

    private var details: [String] {
        var parts: [String] = []
        if isInterview, let level = lesson.level { parts.append(level) }
        parts.append("\(lesson.minutes ?? 25) min")
        if lesson.body.isEmpty {
            parts.append("Download course to open")
            return parts
        }
        if !isInterview {
            let count = LessonOutline.sections(of: lesson).count
            parts.append("\(count) \(count == 1 ? "part" : "parts")")
        }
        parts.append("\(lesson.checks.count) checks")
        return parts
    }
}

// MARK: - Lesson

/// A lesson's text split at its `##` headings, so it can be read one part at a time.
enum LessonOutline {
    struct Section: Identifiable, Hashable {
        let id: Int
        let title: String
        let markdown: String
    }

    static func sections(of lesson: Lesson) -> [Section] {
        var sections: [Section] = []
        var title = "Idea"
        var lines: [String] = []
        var inFence = false

        func flush() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { sections.append(Section(id: sections.count, title: title, markdown: text)) }
            lines = []
        }

        for raw in lesson.body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle() }
            if !inFence, trimmed.hasPrefix("# ") { continue }
            if !inFence, trimmed.hasPrefix("## ") {
                flush()
                title = String(trimmed.dropFirst(3))
                continue
            }
            lines.append(line)
        }
        flush()
        return sections
    }
}

private enum LessonMode: String, CaseIterable {
    case read = "Lesson"
    case code = "Code"
}

/// A lesson or an interview task. On a phone, reading and coding take turns on the
/// whole screen; Run and Check sit at the bottom, under the thumb. On a wide screen
/// they stand side by side.
struct LessonView: View {
    let course: Course
    let lesson: Lesson
    let onOpenProject: (Project) -> Void
    var onNext: ((Lesson) -> Void)?
    @State private var library = CourseLibrary.shared

    var body: some View {
        DownloadGate(packID: "course-\(course.id)") {
            if let resolved = library.courses.first(where: { $0.id == course.id }),
               let current = resolved.lessons.first(where: { $0.id == lesson.id }) {
                InstalledLessonView(course: resolved, lesson: current, onOpenProject: onOpenProject, onNext: onNext)
            }
        }.navigationTitle(lesson.title)
    }
}

private struct InstalledLessonView: View {
    let course: Course
    let lesson: Lesson
    let onOpenProject: (Project) -> Void
    var onNext: ((Lesson) -> Void)?

    @State private var mode: LessonMode = .read
    @State private var code = ""
    @State private var cursor = 0
    @State private var results: [CheckResult] = []
    @State private var reportError: String?
    @State private var hintsShown = 0
    @State private var showSolution = false
    @State private var showTask = true
    @State private var reportKind: ReportKind?
    @State private var visibleSections: Set<Int> = []
    @State private var library = CourseLibrary.shared
    @State private var failure: String?
    @State private var started = Date()
    @State private var bridge = EditorKeyboardBridge()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private let session = RunSession.shared
    private var isInterview: Bool { course.kind == "interview" }
    private var isDone: Bool { library.completed.contains(lesson.id) }
    private var nextLesson: Lesson? { onNext == nil ? nil : library.next(after: lesson, in: course) }
    private var isLastLesson: Bool { library.next(after: lesson, in: course) == nil }
    private var sections: [LessonOutline.Section] { LessonOutline.sections(of: lesson) }
    private var passed: Int { results.filter(\.ok).count }
    private var allPassed: Bool { !results.isEmpty && passed == results.count }
    private var isWide: Bool { sizeClass == .regular }
    private var index: Int { (course.lessons.firstIndex(of: lesson) ?? 0) + 1 }

    enum ReportKind: String, Identifiable {
        case run, check
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        sectionStrip
                        reader
                    }
                    .frame(maxWidth: .infinity)
                    Rectangle().fill(AppTheme.border).frame(width: 1)
                    VStack(spacing: 0) {
                        coder
                        actionBar(showsModes: false)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    if mode == .read {
                        sectionStrip
                        reader
                    } else {
                        coder
                    }
                    actionBar(showsModes: true)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(isInterview ? (lesson.level.map { "\($0) task" } ?? "Interview") : "Lesson \(index) of \(course.lessons.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if isInterview {
                ToolbarItem(placement: .primaryAction) {
                    Text(timerInterval: started...started.addingTimeInterval(TimeInterval((lesson.minutes ?? 25) * 60)), countsDown: true)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.amber)
                }
            }
        }
        .sheet(item: $reportKind) { kind in
            reportSheet(kind: kind)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .onAppear(perform: load)
        .onDisappear(perform: saveDraft)
        .onChange(of: code) { saveDraft() }
    }

    // MARK: Reading

    private var currentSection: Int { visibleSections.min() ?? 0 }

    /// The parts of the lesson, always on screen above the text, never scrolled away.
    private var sectionStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sections) { section in
                        chip(section.title, number: section.id + 1, active: currentSection == section.id && !visibleSections.contains(Self.taskID)) {
                            NotificationCenter.default.post(name: .lessonJump, object: section.id)
                        }
                        .id(section.id)
                    }
                    chip(isInterview ? "Task" : "Your task", number: nil, active: visibleSections.contains(Self.taskID)) {
                        NotificationCenter.default.post(name: .lessonJump, object: Self.taskID)
                    }
                    .id(Self.taskID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: currentSection) { withAnimation { proxy.scrollTo(currentSection, anchor: .center) } }
        }
        .background(AppTheme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    private func chip(_ title: String, number: Int?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let number {
                    Text("\(number)").font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(active ? AppTheme.onBlue : AppTheme.muted)
                } else {
                    Image(systemName: "checklist").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(active ? AppTheme.onBlue : AppTheme.amber)
                }
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(active ? AppTheme.onBlue : AppTheme.primary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(active ? AppTheme.blue : AppTheme.panel, in: Capsule())
            .overlay { if !active { Capsule().stroke(AppTheme.border, lineWidth: 1) } }
        }
        .buttonStyle(.app)
    }

    private static let taskID = 10_000

    private var reader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(isInterview ? course.title.uppercased() : "\(course.title.uppercased()) · \(lesson.minutes ?? 25) MIN")
                        .sectionLabel()
                    Text(lesson.title)
                        .font(.system(size: 30, weight: .bold))
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                    ForEach(LabCatalog.all.filter { ($0.lessons ?? []).contains(lesson.id) }) { lab in
                        NavigationLink(value: lab.id) {
                            Label("Practice in Lab: \(lab.title)", systemImage: "flask")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.app)
                        .accessibilityIdentifier("lesson-lab-\(lab.id)")
                    }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            if section.id > 0 || sections.count > 1 {
                                HStack(spacing: 10) {
                                    Text("\(section.id + 1)")
                                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                                        .foregroundStyle(AppTheme.selectionInk)
                                        .frame(width: 26, height: 26)
                                        .background(AppTheme.selection, in: Circle())
                                    Text(section.title).font(.system(size: 20, weight: .bold))
                                }
                            }
                            MarkdownBlocks(markdown: section.markdown, onRun: runExample)
                        }
                        .padding(.top, 22)
                        .id(section.id)
                        .onScrollVisibilityChange(threshold: 0.2) { visible in
                            if visible { visibleSections.insert(section.id) } else { visibleSections.remove(section.id) }
                        }
                    }
                    taskCard
                        .padding(.top, 28)
                        .id(Self.taskID)
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            if visible { visibleSections.insert(Self.taskID) } else { visibleSections.remove(Self.taskID) }
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onReceive(NotificationCenter.default.publisher(for: .lessonJump)) { note in
                guard let target = note.object as? Int else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundStyle(AppTheme.amber)
                Text(isInterview ? "Task" : "Your task").font(.system(size: 18, weight: .bold))
                Spacer()
                if library.completed.contains(lesson.id) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(AppTheme.mint)
                }
            }
            Text(MarkdownRenderer.inlineText(lesson.task)).font(.system(size: 15.5))
            VStack(alignment: .leading, spacing: 7) {
                ForEach(lesson.checks, id: \.self) { check in
                    let result = results.first { $0.name == check.name }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: result == nil ? "circle" : result!.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(result == nil ? AppTheme.muted : result!.ok ? AppTheme.mint : AppTheme.coral)
                        Text(check.name).font(.system(size: 14)).foregroundStyle(AppTheme.secondary)
                    }
                }
            }
            if !isWide {
                Button {
                    withAnimation(.snappy) { mode = .code }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("Write the code")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.onBlue)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppTheme.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.app)
                .accessibilityIdentifier("lesson-start-coding")
            }
        }
        .padding(16)
        .panelCard(cornerRadius: 18)
    }

    // MARK: Coding

    private var coder: some View {
        VStack(spacing: 0) {
            taskStrip
            if hintsShown > 0, let hint = lesson.hints.prefix(hintsShown).last {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(AppTheme.amber)
                    Text("Hint \(hintsShown) of \(lesson.hints.count). \(hint)")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { hintsShown = 0 } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(AppTheme.muted)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.app)
                    .accessibilityLabel("Hide hint")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.warnPanel)
            }
            SyntaxCodeEditor(
                text: $code,
                cursorOffset: $cursor,
                filePath: "solution.py",
                isEditable: !session.isBusy,
                tracksTyping: false,
                wrapsLines: true,
                navigationTarget: nil,
                keyboardBridge: bridge,
                onRequestCompletion: {}
            )
        }
    }

    /// The task, one tap away while coding. Collapsed, it is a single line.
    private var taskStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showTask.toggle() }
            } label: {
                HStack(spacing: 8) {
                    FileIconView(name: "solution.py")
                    Text(showTask ? "Task" : lesson.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if !results.isEmpty {
                        Text("\(passed)/\(results.count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(allPassed ? AppTheme.mint : AppTheme.coral)
                    }
                    Image(systemName: showTask ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(AppTheme.muted)
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.app)
            .accessibilityIdentifier("lesson-task-toggle")
            if showTask {
                Text(MarkdownRenderer.inlineText(lesson.task))
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 14)
        .background(AppTheme.rail)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    // MARK: Actions

    /// Everything you press sits here, at the bottom, beside the code.
    private func actionBar(showsModes: Bool) -> some View {
        HStack(spacing: 10) {
            if showsModes {
                Picker("Mode", selection: $mode.animation(.snappy)) {
                    ForEach(LessonMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: mode == .code ? 140 : .infinity)
                .layoutPriority(-1)
                .accessibilityIdentifier("lesson-mode")
            }
            if mode == .code || !showsModes {
                Spacer(minLength: 0)
                if session.isBusy {
                    Button(action: session.stop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 46)
                            .background(AppTheme.coral, in: Capsule())
                    }
                    .buttonStyle(.app)
                } else {
                    hintButton
                    Button(action: run) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 46, height: 46)
                            .background(AppTheme.raised, in: Circle())
                    }
                    .buttonStyle(.app)
                    .accessibilityLabel("Run")
                    .accessibilityIdentifier("lesson-run")
                    if isDone, nextLesson != nil || isLastLesson {
                        // Done: checking again stays one tap away, but moving on leads.
                        Button(action: check) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.mint)
                                .frame(width: 46, height: 46)
                                .background(AppTheme.mint.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.app)
                        .accessibilityLabel(isInterview ? "Test again" : "Check again")
                        .accessibilityIdentifier("lesson-check")
                        advanceButton(compact: true)
                    } else {
                        Button(action: check) {
                            Label(isInterview ? "Test" : "Check", systemImage: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.onRun)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 18)
                                .frame(minHeight: 46)
                                .background(AppTheme.run, in: Capsule())
                        }
                        .buttonStyle(.app)
                        .accessibilityIdentifier("lesson-check")
                    }
                }
            } else if isDone, nextLesson != nil || isLastLesson {
                advanceButton(compact: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(AppTheme.panel)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
    }

    /// Moves on once the lesson is done: the next lesson, or back to the course after the last.
    @ViewBuilder
    private func advanceButton(compact: Bool) -> some View {
        if let next = nextLesson, let onNext {
            Button {
                reportKind = nil
                onNext(next)
            } label: {
                HStack(spacing: 6) {
                    Text(compact ? (isInterview ? "Next task" : "Next lesson") : "Next: \(next.title)").lineLimit(1)
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.onBlue)
                .padding(.horizontal, 18)
                .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 46 : 52)
                .background(AppTheme.blue, in: compact ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .fixedSize(horizontal: compact, vertical: false)
            }
            .buttonStyle(.app)
            .accessibilityIdentifier(compact ? "lesson-next-bar" : "lesson-next")
        } else if isLastLesson {
            Button {
                reportKind = nil
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                    Text(compact ? "Finish" : "Course complete · back to the course").lineLimit(1)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppTheme.onBlue)
                .padding(.horizontal, 18)
                .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 46 : 52)
                .background(AppTheme.mint, in: compact ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .fixedSize(horizontal: compact, vertical: false)
            }
            .buttonStyle(.app)
            .accessibilityIdentifier(compact ? "lesson-finish-bar" : "lesson-finish")
        }
    }

    @ViewBuilder
    private var hintButton: some View {
        if hintsShown < lesson.hints.count {
            Button { hintsShown += 1 } label: {
                Image(systemName: "lightbulb")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.amber)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.raised, in: Circle())
            }
            .buttonStyle(.app)
            .accessibilityLabel("Hint \(hintsShown + 1) of \(lesson.hints.count)")
        } else if !showSolution, !lesson.hints.isEmpty {
            Menu {
                Button("Show the solution", systemImage: "eye") { showSolution = true; code = lesson.solution }
            } label: {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.amber)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.raised, in: Circle())
            }
            .accessibilityLabel("Solution")
        }
    }

    // MARK: Report

    private func reportSheet(kind: ReportKind) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if kind == .check {
                        checkSummary
                    }
                    outputBlock(kind: kind)
                    if let failure { Text(failure).font(.system(size: 13)).foregroundStyle(AppTheme.coralInk) }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Pinned, so it is on screen at every sheet height and never under the explanation.
                if kind == .check, allPassed, !session.isBusy, nextLesson != nil || isLastLesson {
                    advanceButton(compact: false)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(AppTheme.panel)
                        .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 1) }
                }
            }
            .navigationTitle(reportTitle(kind: kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { reportKind = nil } }
            }
        }
        .accessibilityIdentifier("lesson-report")
    }

    private func reportTitle(kind: ReportKind) -> String {
        if session.isBusy { return kind == .check ? "Checking…" : "Running…" }
        if kind == .run { return "Output" }
        if reportError != nil { return "Could not check" }
        return allPassed ? "All checks passed" : "\(passed) of \(results.count) checks passed"
    }

    @ViewBuilder
    private var checkSummary: some View {
        if let reportError {
            Text(reportError).font(.system(size: 13.5, design: .monospaced)).foregroundStyle(AppTheme.coralInk)
        }
        if allPassed {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isInterview ? "Task solved" : "Lesson complete").font(.system(size: 18, weight: .bold))
                    Text(nextLesson.map { "Up next: \($0.title)" } ?? (isLastLesson ? "That was the last one in \(course.title)." : "Saved to your progress."))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lesson-complete")
        }
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(result.ok ? AppTheme.mint : AppTheme.coral)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name).font(.system(size: 15, weight: .semibold))
                        if !result.ok, !result.message.isEmpty {
                            Text(result.message)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(AppTheme.coralInk)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                if index < results.count - 1 { Divider().padding(.leading, 39) }
            }
        }
        .panelCard()
        if allPassed {
            VStack(alignment: .leading, spacing: 6) {
                Text("Why this works").font(.system(size: 15, weight: .bold))
                MarkdownBlocks(markdown: lesson.explanation)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
        }
        if !results.isEmpty {
            Button(action: keepAsProject) {
                Text(allPassed ? "Keep as a project" : "Debug in a project")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.app)
        }
    }

    @ViewBuilder
    private func outputBlock(kind: ReportKind) -> some View {
        let text = Self.outputText(session.output)
        if !text.isEmpty || kind == .run {
            VStack(alignment: .leading, spacing: 6) {
                Text("OUTPUT").sectionLabel()
                Text(text.isEmpty ? (session.isBusy ? "…" : "Nothing was printed.") : text)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(text.isEmpty ? AppTheme.muted : AppTheme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private static func outputText(_ chunks: [OutputChunk]) -> String {
        let text = chunks.filter { $0.kind != .system }.map(\.text).joined()
        return text.count > 8_000 ? "…" + String(text.suffix(8_000)) : text
    }

    // MARK: Work

    private func load() {
        library.markOpened(lesson)
        let draft = CourseLibrary.draftURL(lesson)
        code = (try? String(contentsOf: draft, encoding: .utf8)) ?? lesson.starter
        session.onCustom = nil
        if isInterview, !isWide { mode = .code }
        #if DEBUG
        // For screenshots: -lessonMode code, -lessonCheck YES.
        if UserDefaults.standard.string(forKey: "lessonMode") == "code" { mode = .code }
        if UserDefaults.standard.bool(forKey: "lessonCheck") {
            Task { try? await Task.sleep(for: .seconds(2)); check() }
        }
        #endif
    }

    private func saveDraft() {
        guard !code.isEmpty else { return }
        try? code.write(to: CourseLibrary.draftURL(lesson), atomically: true, encoding: .utf8)
    }

    private func run() {
        saveDraft()
        bridge.dismissKeyboard()
        let url = CourseLibrary.draftURL(lesson)
        submitScript(url, label: lesson.title)
    }

    /// Runs one of the lesson's own examples, as it is printed in the text.
    private func runExample(_ source: String) {
        let url = CourseLibrary.draftURL(lesson).deletingLastPathComponent().appending(path: "example.py")
        try? source.write(to: url, atomically: true, encoding: .utf8)
        submitScript(url, label: "Example")
    }

    private func submitScript(_ url: URL, label: String) {
        guard !session.isBusy else { return }
        session.onCustom = nil
        session.clearOutput()
        reportKind = .run
        session.submit(
            ["kind": "script", "path": url.path, "root": url.deletingLastPathComponent().path, "cwd": url.deletingLastPathComponent().path],
            label: label
        )
    }

    private func check() {
        guard !session.isBusy else { return }
        saveDraft()
        bridge.dismissKeyboard()
        results = []
        reportError = nil
        session.clearOutput()
        reportKind = .check
        let url = CourseLibrary.draftURL(lesson)
        session.onCustom = { [lesson] kind, data in
            guard kind == "lesson_result", let report = try? JSONDecoder().decode(LessonReport.self, from: data) else { return }
            results = report.results
            reportError = report.error
            if !report.results.isEmpty, report.results.allSatisfy(\.ok) {
                CourseLibrary.shared.markCompleted(lesson)
            }
        }
        session.submit(
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
        if course.id == "finetuning-projects",
           let offset = course.lessons.firstIndex(where: { $0.id == lesson.id }),
           offset < ProjectTemplate.finetuning.count {
            let selected = ProjectTemplate.finetuning[offset]
            do {
                let project = try ProjectStore.shared.create(name: lesson.id, template: selected)
                let name = selected.id.replacingOccurrences(of: "finetune-", with: "")
                try code.write(to: project.url.appending(path: "finetune_projects/\(name).py"), atomically: true, encoding: .utf8)
                reportKind = nil; onOpenProject(project)
            } catch { failure = error.localizedDescription }
            return
        }
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
            reportKind = nil
            let project = try ProjectStore.shared.create(name: lesson.id, template: template)
            let dependencies = ContentStore.shared.catalog.pack("course-\(course.id)")?.dependencies ?? []
            if !dependencies.isEmpty {
                try JSONEncoder().encode(dependencies).write(to: project.url.appending(path: "pythilo-packages.json"), options: .atomic)
            }
            onOpenProject(project)
        } catch {
            failure = error.localizedDescription
        }
    }
}

extension Notification.Name {
    static let lessonJump = Notification.Name("pythilo.lessonJump")
}

/// Markdown with code blocks in the editor's colours. Examples can run in place.
struct MarkdownBlocks: View {
    let markdown: String
    var onRun: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownRenderer.blocks(of: markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .code(source):
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HighlightedCode(source: source)
                                .padding(14)
                        }
                        if let onRun {
                            Button { onRun(source) } label: {
                                Label("Run example", systemImage: "play.fill")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(AppTheme.selectionInk)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.app)
                            .background(AppTheme.raised.opacity(0.6))
                        }
                    }
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
                case .blank:
                    EmptyView()
                case let .heading(_, text):
                    Text(MarkdownRenderer.inlineText(text))
                        .font(.system(size: 17, weight: .bold))
                        .padding(.top, 4)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(AppTheme.blue).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(MarkdownRenderer.inlineText(text))
                            .font(.system(size: 16))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case let .paragraph(text):
                    Text(MarkdownRenderer.inlineText(text))
                        .font(.system(size: 16.5))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
