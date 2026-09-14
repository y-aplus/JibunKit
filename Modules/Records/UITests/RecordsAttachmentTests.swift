import XCTest

@MainActor
final class RecordsAttachmentTests: XCTestCase {
    func testImportPreviewPersistAndDeleteAttachment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP", "--attachment-fixture"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 15))
            element.tap()
        }
        let title = "Attachment-" + UUID().uuidString.prefix(8)
        func row() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "records.row.", String(title))).firstMatch
        }
        func attachment() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "records.attachment.")).firstMatch
        }
        func selectFixture() {
            tap(app.tabBars["DOC.browsingModeTabBar"].buttons["ブラウズ"])
            tap(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "このiPhone内")).firstMatch)
            let fixture = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "attachment-fixture")).firstMatch
            XCTAssertTrue(fixture.waitForExistence(timeout: 15), app.debugDescription)
            // Files icon cells include the filename and metadata below the thumbnail.
            // Their center can land outside the file's opening hit target.
            let thumbnail = fixture.images.firstMatch
            XCTAssertTrue(thumbnail.waitForExistence(timeout: 15))
            // The thumbnail is a decorative accessibility child, so isHittable can
            // be false even though its frame is visible inside the interactive cell.
            let thumbnailFrame = thumbnail.frame
            XCTAssertFalse(thumbnailFrame.isEmpty)
            XCTAssertTrue(app.frame.contains(thumbnailFrame), app.debugDescription)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: thumbnailFrame.midX - app.frame.minX,
                                     dy: thumbnailFrame.midY - app.frame.minY)).tap()
            let selectionScreenshot = XCTAttachment(screenshot: app.screenshot())
            selectionScreenshot.name = "records-files-after-thumbnail-tap"
            selectionScreenshot.lifetime = .keepAlways
            add(selectionScreenshot)
            XCTAssertTrue(app.collectionViews["File View"].waitForNonExistence(timeout: 15),
                          "Files must finish selection before checking the imported attachment.\n" + app.debugDescription)
        }
        tap(app.buttons["records.fixture.export"])
        // A fresh Files process can open at Locations rather than the last
        // folder. Run 34802338245's hierarchy showed that state, with no Save
        // control until a destination is selected. Do not depend on another
        // test having visited On My iPhone first.
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["保存", "Save"])).firstMatch
        let localDestination = app.cells["DOC.sidebar.item.このiPhone内"]
        let destinationReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in save.exists || localDestination.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [destinationReady], timeout: 20), .completed, app.debugDescription)
        if localDestination.exists { tap(localDestination) }
        tap(save)
        XCTAssertTrue(app.buttons["records.fixture.saved"].waitForExistence(timeout: 15), app.debugDescription)
        tap(app.buttons["records.fixture.import"])
        selectFixture()
        XCTAssertTrue(app.staticTexts["records.fixture.result"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.staticTexts["records.fixture.result"].label, "Fixture imported")
        tap(app.buttons["records.add"])
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.buttons["records.save"])
        tap(row())
        tap(app.buttons["records.attach"])
        selectFixture()
        XCTAssertTrue(attachment().waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(attachment().label.contains("attachment-fixture.txt"))
        tap(attachment())
        let previewPresented = app.buttons["完了"].waitForExistence(timeout: 15)
        XCTAssertFalse(app.staticTexts["records.attachment.error"].exists, app.debugDescription)
        #if targetEnvironment(simulator)
        // Device e01836b passed preview on 2026-09-09. Keep this known simulator
        // failure visible without preventing persistence/deletion verification.
        // Strict matching deliberately asks us to remove this once it succeeds.
        XCTExpectFailure("Simulator Quick Look: docs/verification/2026-09-08-file-backup.md") {
            XCTAssertTrue(previewPresented, "Quick Look presentation is still unresolved on Simulator")
        }
        #else
        XCTAssertTrue(previewPresented)
        #endif
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = previewPresented ? "records-attachment-preview" : "records-preview-known-failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if previewPresented { tap(app.buttons["完了"]) }
        app.terminate()
        app.launch()
        tap(row())
        XCTAssertTrue(attachment().waitForExistence(timeout: 10))
        attachment().swipeLeft()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["キャンセル"])
        XCTAssertTrue(attachment().exists)
        attachment().swipeLeft()
        tap(app.buttons["削除"])
        tap(app.alerts.buttons["削除"])
        XCTAssertTrue(attachment().waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        tap(row())
        XCTAssertTrue(app.buttons["records.attach"].waitForExistence(timeout: 10))
        XCTAssertFalse(attachment().exists)
    }
}
