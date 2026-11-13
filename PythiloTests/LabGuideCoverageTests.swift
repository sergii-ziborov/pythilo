import XCTest
@testable import Pythilo

/// Every Lab ships with its About guide and an illustration, inside the app bundle.
final class LabGuideCoverageTests: XCTestCase {
    func testEveryLabHasACompleteGuide() throws {
        XCTAssertGreaterThanOrEqual(LabCatalog.all.count, 136)
        for lab in LabCatalog.all {
            let guide = try XCTUnwrap(LabGuides.guide(for: lab.id), "\(lab.id) has no guide")
            XCTAssertGreaterThan(guide.idea.split(separator: " ").count, 50, lab.id)
            XCTAssertTrue((4...6).contains(guide.steps.count), lab.id)
            XCTAssertTrue((2...3).contains(guide.cost.count), lab.id)
            XCTAssertEqual(guide.uses.count, 3, lab.id)
            XCTAssertEqual(guide.pitfalls.count, 3, lab.id)
            XCTAssertFalse(guide.watch.isEmpty, lab.id)
            XCTAssertFalse(guide.costNote.isEmpty, lab.id)
        }
    }

    func testEveryLabHasAnIllustration() throws {
        for lab in LabCatalog.all {
            let image = try XCTUnwrap(LabGuides.image(for: lab), "\(lab.id) has no illustration")
            XCTAssertGreaterThan(image.size.width, 600, lab.id)
        }
        let folder = Bundle.main.bundleURL.appending(path: "LabGuides/topics")
        for topic in LabCatalog.topics {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "\(topic.id).heic").path), topic.id)
        }
    }
}
