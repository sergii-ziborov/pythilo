import XCTest
@testable import Pythilo

@MainActor final class ProjectDependencyTests: XCTestCase {
    func testExistingProjectsGainDependenciesWithoutChangingTheirCode() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "import os, torch as t\nfrom pydantic import BaseModel\n"
        try source.write(to: root.appending(path: "main.py"), atomically: true, encoding: .utf8)
        let project = Project(url: root)
        XCTAssertEqual(ProjectDependencies.refresh(project), ["runtime-torch", "runtime-web"])
        XCTAssertEqual(project.requiredPacks, ["runtime-torch", "runtime-web"])
        XCTAssertEqual(try String(contentsOf: root.appending(path: "main.py"), encoding: .utf8), source)
        try "import numpy as np\n".write(to: root.appending(path: "later.py"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDependencies.refresh(project), ["runtime-numpy", "runtime-torch", "runtime-web"])
    }

    func testLocalModulesAndDependencyFoldersAreNotExternalPackages() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: "node_modules"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (file, code) in ["main.py": "import torch\n# import numpy\n", "torch.py": "value = 1\n", "node_modules/library.py": "import sympy\n"] {
            try code.write(to: root.appending(path: file), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(ProjectDependencies.refresh(Project(url: root)), [])
        XCTAssertEqual(ProjectTemplate.coreML.requiredPacks, ["runtime-numpy"])
    }
}
