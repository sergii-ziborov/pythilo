import Foundation
import PythiloGit
import XCTest

final class MergeTests: XCTestCase {
    private var root: URL!
    private var repository: ProjectRepository!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "pythilo-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        repository = ProjectRepository(worktree: root)
        try repository.initialize()
        try commit("app.py", "def greet():\n    return 'hi'\n\nprint(greet())\n", "First")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ text: String) throws {
        try text.write(to: root.appending(path: path), atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @discardableResult
    private func commit(_ path: String, _ text: String, _ message: String) throws -> GitCommitSummary {
        try write(path, text)
        try repository.stage([path])
        return try repository.commit(message: message, author: "Ada", email: "ada@example.com")
    }

    func testFastForward() throws {
        try repository.createBranch("feature")
        try repository.switchBranch("feature")
        try commit("notes.txt", "one\n", "Notes")
        try repository.switchBranch("main")
        let outcome = try repository.merge("feature", author: "Ada", email: "ada@example.com")
        XCTAssertEqual(outcome.kind, .fastForward)
        XCTAssertEqual(try read("notes.txt"), "one\n")
        XCTAssertEqual(try repository.history().count, 2)
        XCTAssertEqual(try repository.merge("feature", author: "Ada", email: "ada@example.com").kind, .upToDate)
    }

    func testCleanMergeMakesAMergeCommit() throws {
        try repository.createBranch("feature")
        try repository.switchBranch("feature")
        try commit("notes.txt", "from feature\n", "Feature notes")
        try repository.switchBranch("main")
        try commit("todo.txt", "from main\n", "Main todo")
        let outcome = try repository.merge("feature", author: "Ada", email: "ada@example.com")
        XCTAssertEqual(outcome.kind, .merged)
        XCTAssertEqual(try read("notes.txt"), "from feature\n")
        XCTAssertEqual(try read("todo.txt"), "from main\n")
        XCTAssertEqual(try repository.history().count, 4)
        XCTAssertFalse(repository.isMerging)
        XCTAssertTrue(try repository.snapshot().changes.isEmpty)
    }

    func testConflictStopsThenCommitFinishesTheMerge() throws {
        try repository.createBranch("feature")
        try repository.switchBranch("feature")
        try commit("app.py", "def greet():\n    return 'hello'\n\nprint(greet())\n", "Hello")
        try repository.switchBranch("main")
        try commit("app.py", "def greet():\n    return 'hey'\n\nprint(greet())\n", "Hey")
        let outcome = try repository.merge("feature", author: "Ada", email: "ada@example.com")
        XCTAssertEqual(outcome.kind, .conflicts)
        XCTAssertEqual(outcome.conflicts, ["app.py"])
        XCTAssertTrue(repository.isMerging)
        let marked = try read("app.py")
        XCTAssertTrue(marked.contains("<<<<<<<") && marked.contains(">>>>>>>"), marked)
        XCTAssertThrowsError(try repository.commit(message: "Too early", author: "Ada", email: "ada@example.com"))

        try write("app.py", "def greet():\n    return 'hello, hey'\n\nprint(greet())\n")
        try repository.stage(["app.py"])
        try repository.commit(message: "Merge feature", author: "Ada", email: "ada@example.com")
        XCTAssertFalse(repository.isMerging)
        XCTAssertEqual(try repository.history().count, 4)
        XCTAssertEqual(try repository.merge("feature", author: "Ada", email: "ada@example.com").kind, .upToDate)
    }

    func testAbortPutsTheFilesBack() throws {
        try repository.createBranch("feature")
        try repository.switchBranch("feature")
        try commit("app.py", "print('feature')\n", "Feature")
        try repository.switchBranch("main")
        let before = try commit("app.py", "print('main')\n", "Main")
        XCTAssertEqual(try repository.merge("feature", author: "Ada", email: "ada@example.com").kind, .conflicts)
        try repository.abortMerge()
        XCTAssertFalse(repository.isMerging)
        XCTAssertEqual(try read("app.py"), "print('main')\n")
        XCTAssertEqual(try repository.snapshot().head, before.id)
        XCTAssertThrowsError(try repository.abortMerge())
    }

    func testMergeRefusesUncommittedEdits() throws {
        try repository.createBranch("feature")
        try write("app.py", "print('unsaved')\n")
        XCTAssertThrowsError(try repository.merge("feature", author: "Ada", email: "ada@example.com")) { error in
            XCTAssertTrue("\(error.localizedDescription)".contains("Commit or discard"))
        }
        XCTAssertEqual(try read("app.py"), "print('unsaved')\n")
    }

    func testRebaseReplaysCommits() throws {
        try repository.createBranch("feature")
        try repository.switchBranch("feature")
        try commit("notes.txt", "one\n", "Notes")
        try commit("notes.txt", "one\ntwo\n", "More notes")
        try repository.switchBranch("main")
        try commit("todo.txt", "main\n", "Todo")
        try repository.switchBranch("feature")
        let message = try repository.rebase(onto: "main", author: "Ada", email: "ada@example.com")
        XCTAssertEqual(message, "Replayed 2 commits on top of main.")
        XCTAssertEqual(try read("todo.txt"), "main\n")
        XCTAssertEqual(try read("notes.txt"), "one\ntwo\n")
        let history = try repository.history()
        XCTAssertEqual(history.map(\.message), ["More notes", "Notes", "Todo", "First"])
    }

    func testRebaseConflictLeavesTheBranchAlone() throws {
        try repository.createBranch("feature")
        try repository.switchBranch("feature")
        let mine = try commit("app.py", "print('feature')\n", "Feature")
        try repository.switchBranch("main")
        try commit("app.py", "print('main')\n", "Main")
        try repository.switchBranch("feature")
        XCTAssertThrowsError(try repository.rebase(onto: "main", author: "Ada", email: "ada@example.com")) { error in
            XCTAssertTrue(error.localizedDescription.contains("undone"), error.localizedDescription)
        }
        XCTAssertEqual(try repository.snapshot().branch, "feature")
        XCTAssertEqual(try repository.snapshot().head, mine.id)
        XCTAssertEqual(try read("app.py"), "print('feature')\n")
    }
}
