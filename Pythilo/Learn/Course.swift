import Foundation
import Observation

struct LessonCheck: Codable, Hashable, Sendable {
    let name: String
    let code: String
}

struct Lesson: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let level: String?
    let minutes: Int?
    let body: String
    let task: String
    let starter: String
    let solution: String
    let checks: [LessonCheck]
    let hints: [String]
    let explanation: String
}

struct Course: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let kind: String
    let lessons: [Lesson]
}

struct CheckResult: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let ok: Bool
    let message: String
    var id: String { name }
}

struct LessonReport: Decodable, Sendable {
    let id: String
    let results: [CheckResult]
    let error: String?
}

/// Lightweight course previews, downloaded lessons and progress kept on this device.
@MainActor
@Observable
final class CourseLibrary {
    static let shared = CourseLibrary()

    private(set) var courses: [Course] = []
    private(set) var completed: Set<String>
    private(set) var lastLessonID: String?

    private let defaults = UserDefaults.standard

    init() {
        completed = Set(defaults.stringArray(forKey: "pythilo.completedLessons") ?? [])
        lastLessonID = defaults.string(forKey: "pythilo.lastLesson")
        reload()
    }

    func reload() {
        courses = DownloadCatalog.bundled.courses.map { preview in
            guard let folder = ContentStore.shared.location("course-\(preview.id)"),
                  let data = try? Data(contentsOf: folder.appending(path: "course.json")),
                  let course = try? JSONDecoder().decode(Course.self, from: data), course.id == preview.id else { return preview }
            return course
        }
    }

    var paths: [Course] { courses.filter { $0.kind == "path" } }
    var interview: Course? { courses.first { $0.kind == "interview" } }

    func completedCount(_ course: Course) -> Int {
        course.lessons.filter { completed.contains($0.id) }.count
    }

    func markCompleted(_ lesson: Lesson) {
        completed.insert(lesson.id)
        defaults.set(Array(completed), forKey: "pythilo.completedLessons")
    }

    func markOpened(_ lesson: Lesson) {
        lastLessonID = lesson.id
        defaults.set(lesson.id, forKey: "pythilo.lastLesson")
    }

    var lastLesson: (Course, Lesson)? {
        guard let lastLessonID else { return nil }
        for course in courses {
            if let lesson = course.lessons.first(where: { $0.id == lastLessonID }) { return (course, lesson) }
        }
        return nil
    }

    /// Your own edits to a lesson's code, kept apart from the course, so a course
    /// update never overwrites them.
    static func draftURL(_ lesson: Lesson) -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "LessonDrafts/\(lesson.id)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "solution.py")
    }
}
