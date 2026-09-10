import XCTest

@MainActor
final class WebStorageOwnershipUITests: XCTestCase {
    func testPageStorageSurvivesBackgroundRestartAndOwnerClearPreservesOther() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

        func launch() {
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        }
        func tap(_ identifier: String) {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
            button.tap()
        }
        func open(_ owner: String) {
            let listButton = app.buttons["miniapp.\(owner)"]
            if listButton.waitForExistence(timeout: 2) {
                listButton.tap()
            } else {
                tap("miniapp.switch.open")
                tap("miniapp.switch.\(owner)")
            }
            let ready = app.staticTexts.matching(identifier: "web-storage.page")
                .matching(NSPredicate(format: "label == %@", "page-ready")).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 20), app.debugDescription)
        }
        func expect(_ expected: String) {
            let result = app.staticTexts.matching(identifier: "web-storage.result")
                .matching(NSPredicate(format: "label == %@", expected)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 15), app.debugDescription)
            print("WEB-STORAGE-OWNERSHIP \(expected)")
        }
        func clear(_ owner: String) {
            tap("web-storage.clear")
            expect("removed owner=\(owner)")
        }
        func writeAndObserve(_ owner: String) {
            tap("web-storage.write")
            expect("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
            tap("web-storage.read")
            expect("local=\(owner) cookie=\(owner) indexeddb=\(owner)")
        }
        func backgroundAndTerminate() {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 15))
            app.terminate()
        }

        launch()
        for owner in ["web-storage-owner-a", "web-storage-owner-b"] {
            open(owner)
            clear(owner)
            writeAndObserve(owner)
        }

        backgroundAndTerminate()
        launch()
        open("web-storage-owner-a")
        tap("web-storage.read")
        expect("local=web-storage-owner-a cookie=web-storage-owner-a indexeddb=web-storage-owner-a")
        clear("web-storage-owner-a")
        tap("web-storage.read")
        expect("local=missing cookie=missing indexeddb=missing")

        backgroundAndTerminate()
        launch()
        open("web-storage-owner-b")
        tap("web-storage.read")
        expect("local=web-storage-owner-b cookie=web-storage-owner-b indexeddb=web-storage-owner-b")
        clear("web-storage-owner-b")
    }
}
