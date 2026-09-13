import Foundation
import XCTest

final class SourceCompositionTests: XCTestCase {
    func testStandaloneHostsImportAndLinkOnlyTheirOwnedPackage() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixture = directory.appendingPathComponent("Project.swift.fixture")
        let projectURL = FileManager.default.fileExists(atPath: fixture.path)
            ? fixture : directory.appendingPathComponent("Project.swift")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let aHost = try String(contentsOf: directory.appendingPathComponent("StandaloneAHostApp.swift"), encoding: .utf8)
        let bHost = try String(contentsOf: directory.appendingPathComponent("StandaloneBHostApp.swift"), encoding: .utf8)
        let combined = try String(contentsOf: directory.appendingPathComponent("HostApp.swift"), encoding: .utf8)

        XCTAssertTrue(aHost.contains("import WidgetFeatureA"))
        XCTAssertFalse(aHost.contains("WidgetFeatureB"))
        XCTAssertTrue(bHost.contains("import WidgetFeatureB"))
        XCTAssertFalse(bHost.contains("WidgetFeatureA"))
        XCTAssertTrue(combined.contains("import WidgetFeatureA"))
        XCTAssertTrue(combined.contains("import WidgetFeatureB"))
        XCTAssertTrue(project.contains("source: \"StandaloneAHostApp.swift\""))
        XCTAssertTrue(project.contains("source: \"StandaloneBHostApp.swift\""))
        XCTAssertTrue(project.contains("source: \"HostApp.swift\""))
        XCTAssertFalse(bHost.contains("widget-fixture.update-a"))
    }
}
