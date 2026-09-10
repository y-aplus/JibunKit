import XCTest

/// Copied only into the temporary Notes-integrated host by CI.
@MainActor
final class GeneratedFeatureUITests: XCTestCase {
    func testNativeNotificationRequestPayloadsReachOnlyTheirOwners() {
        continueAfterFailure = false
        // Both fixtures now validate the native request before marking receipt.
        // Foreground notifications are removed before testing the action card.
        verifyForegroundNotificationsConsultOnlyTheirOwner()
        verifyNativeCustomActionReachesOwnerWithoutReplacingVisibleFeature()
    }

    func testSceneIdleRequestSuspendsResumesAndPreservesOtherOwner() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["JIBUNKIT_SCENE_IDLE_PROBE"] = "1"
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func expect(_ id: String, _ value: String) {
            let text = app.staticTexts.matching(identifier: id)
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        func read(_ value: String) {
            tap("scene.idle.read")
            expect("scene.idle.result", value)
        }
        func select(_ owner: String) {
            tap("miniapp.switch.open")
            tap("miniapp.switch.\(owner)")
        }
        tap("miniapp.lifecycle-a")
        tap("scene.idle.request")
        read("disabled:lifecycle-a")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        expect("scene.idle.background", "released")
        read("disabled:lifecycle-a")
        select("lifecycle-b")
        read("enabled:")
        tap("scene.idle.manual")
        read("disabled:lifecycle-b")
        select("lifecycle-a")
        read("disabled:lifecycle-a,lifecycle-b")
        tap("scene.idle.shutdown")
        expect("scene.idle.result", "disabled:lifecycle-b")
        select("lifecycle-b")
        tap("scene.idle.manual-release")
        read("enabled:")
        select("lifecycle-a")
        tap("scene.idle.request")
        expect("scene.idle.error", "closed")
        read("enabled:")
    }

    func testSceneActivityFollowsSelectionAndBackgroundWithoutStoppingOtherWork() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["JIBUNKIT_SCENE_ACTIVITY_PROBE"] = "1"
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func expect(_ id: String, _ value: String) {
            let text = app.staticTexts.matching(identifier: id)
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        tap("miniapp.lifecycle-a")
        // B has never constructed its root, but receives this scene's initial state.
        expect("scene.activity.status", "A=active:1 B=active:0")
        expect("scene.activity.identity", "same scene")
        tap("scene.activity.start")
        expect("scene.activity.work", "running")
        tap("miniapp.switch.open")
        tap("miniapp.switch.lifecycle-b")
        expect("scene.activity.status", "A=active:0 B=active:1")
        expect("scene.activity.work", "running")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        expect("scene.activity.background", "both background")
        expect("scene.activity.status", "A=active:0 B=active:1")
        expect("scene.activity.work", "running")
        tap("miniapp.switch.open")
        tap("miniapp.switch.list")
        tap("miniapp.lifecycle-a")
        expect("scene.activity.status", "A=active:1 B=active:0")
        expect("scene.activity.work", "running")
    }

    func testSceneNavigationObjectsAndNotificationTargetStayIndependent() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func expect(_ value: String) {
            let text = app.staticTexts.matching(identifier: "scene.navigation.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        tap("miniapp.lifecycle-a")
        tap("webdata.open")
        tap("scene.navigation.open")
        expect("A=0 B=0")
        tap("scene.navigation.a.open")
        tap("scene.navigation.a.push")
        tap("scene.navigation.b.open")
        tap("scene.navigation.b.push")
        expect("A=2 B=2")
        tap("scene.navigation.route")
        expect("A=2 B=0")
        tap("scene.navigation.b.open")
        expect("A=2 B=2")
        tap("scene.navigation.activate-a")
        tap("scene.navigation.route")
        expect("A=0 B=2")
        tap("scene.navigation.a.open")
        tap("scene.navigation.remove-a")
        tap("scene.navigation.route")
        expect("A=2 B=0")
    }

    func testFeatureNavigationRetainsPathsAcrossSwitches() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["JIBUNKIT_NAVIGATION_PROBE"] = "1"
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func expect(_ page: String) {
            let text = app.staticTexts.matching(identifier: "navigation.retention.page")
                .matching(NSPredicate(format: "label == %@", page)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        func select(_ id: String) {
            tap("miniapp.switch.open")
            tap("miniapp.switch." + id)
        }
        tap("miniapp.lifecycle-a")
        expect("lifecycle-a:0")
        tap("navigation.retention.check")
        XCTAssertTrue(app.staticTexts.matching(identifier: "navigation.retention.contract")
            .matching(NSPredicate(format: "label == %@", "passed")).firstMatch.waitForExistence(timeout: 10))
        tap("navigation.retention.next")
        expect("lifecycle-a:1")
        tap("navigation.retention.next")
        expect("lifecycle-a:2")
        select("lifecycle-b")
        expect("lifecycle-b:0")
        tap("navigation.retention.next")
        expect("lifecycle-b:1")
        select("lifecycle-a")
        expect("lifecycle-a:2")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expect("lifecycle-a:1")
        select("list")
        tap("miniapp.lifecycle-a")
        expect("lifecycle-a:1")
        select("reset")
        expect("lifecycle-a:0")
        select("lifecycle-b")
        expect("lifecycle-b:1")
        tap("navigation.retention.invalid")
        expect("lifecycle-b:1")
        tap("navigation.retention.route")
        expect("lifecycle-a:7")
        XCUIDevice.shared.system.open(URL(string: "jibunkit://mini-app/lifecycle-a")!)
        expect("lifecycle-a:0")
        select("lifecycle-b")
        expect("lifecycle-b:1")
    }

    func testPersistentHTTPPasswordsSurviveRestartAndOtherOwnerLogout() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func expect(_ value: String) {
            let text = app.staticTexts.matching(identifier: "network.passwords.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("webdata.open")
            tap("network.passwords.open")
            expect("ready")
        }
        func restart() { app.terminate(); app.launch() }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("network.passwords.clear")
            expect("cleared")
            tap("network.passwords.save")
            expect("saved")
            restart()
        }
        open("lifecycle-a")
        tap("network.passwords.read")
        expect("lifecycle-a")
        tap("network.passwords.clear")
        expect("cleared")
        restart()
        open("lifecycle-a")
        tap("network.passwords.read")
        expect("missing")
        restart()
        open("lifecycle-b")
        tap("network.passwords.read")
        expect("lifecycle-b")
        tap("network.passwords.clear")
        expect("cleared")
    }

    func testPersistentHTTPCookiesSurviveRestartAndOtherOwnerLogout() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func expect(_ value: String) {
            let text = app.staticTexts.matching(identifier: "network.cookies.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("webdata.open")
            tap("network.cookies.open")
            expect("ready")
        }
        func restart() { app.terminate(); app.launch() }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("network.cookies.clear")
            expect("cleared")
            tap("network.cookies.save")
            expect("saved")
            restart()
        }
        open("lifecycle-a")
        tap("network.cookies.read")
        expect("lifecycle-a|secure=true|httpOnly=true")
        tap("network.cookies.clear")
        expect("cleared")
        restart()
        open("lifecycle-a")
        tap("network.cookies.read")
        expect("missing")
        restart()
        open("lifecycle-b")
        tap("network.cookies.read")
        expect("lifecycle-b|secure=true|httpOnly=true")
        tap("network.cookies.clear")
        expect("cleared")
    }

    func testRestoreFailuresDescribeDataAndRuntimeStateWithoutChangingOtherFeature() {
        let messages = [
            "stop": "実行中の処理を停止できなかったため、このアプリの保存データは復元していません。",
            "stop-after-shutdown": "実行中の処理を停止できなかったため、このアプリの保存データは復元していません。",
            "stop-recovery": "保存データは復元していません。このアプリの停止に失敗し、利用できる状態へ戻すこともできませんでした。",
            "apply": "保存データの復元に失敗しました。一部が変更されている可能性があります。",
            "resume": "保存データは復元しましたが、このアプリの再開に失敗しました。",
            "both": "保存データの復元と、このアプリの再開に失敗しました。"
        ]
        for fault in ["stop", "stop-after-shutdown", "stop-recovery", "apply", "resume", "both"] {
            let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
            app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
            app.launchEnvironment["JIBUNKIT_RESTORE_FAULT"] = fault
            app.launch()
            func tap(_ id: String) {
                let button = app.buttons[id]
                XCTAssertTrue(button.waitForExistence(timeout: 10))
                button.tap()
            }
            for owner in ["lifecycle-b", "lifecycle-a"] {
                tap("miniapp.\(owner)")
                tap("lifecycle.task.start")
                if owner == "lifecycle-b" { app.navigationBars.buttons["ミニアプリ"].tap() }
            }
            tap("runtime.restore.open")
            let selection = app.switches["backup.restore.lifecycle-a"]
            XCTAssertTrue(selection.waitForExistence(timeout: 10))
            selection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            tap("backup.restore")
            app.alerts.buttons["置き換えて復元"].tap()
            let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", messages[fault]!)).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 10), "\(fault): \(app.debugDescription)")
            XCTAssertTrue(message.label.contains("後続のアプリは変更していません。"))
            tap("閉じる")
            XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, fault.hasPrefix("stop") ? "original" : "restored")
            XCTAssertEqual(app.staticTexts["lifecycle.task.status"].label,
                           fault == "stop" ? "running" : ["apply", "stop-after-shutdown"].contains(fault) ? "idle" : "closed")
            if fault == "stop-after-shutdown" {
                tap("lifecycle.task.start")
                XCTAssertEqual(app.staticTexts["lifecycle.task.status"].label, "running")
                tap("lifecycle.task.complete")
            }
            app.navigationBars.buttons["ミニアプリ"].tap()
            tap("miniapp.lifecycle-b")
            XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "original")
            XCTAssertEqual(app.staticTexts["lifecycle.task.status"].label, "running")
            tap("lifecycle.task.complete")
            app.terminate()
        }
    }

    func testOrdinaryStoreAccessBlocksRestoreUntilFinishedAndPreservesOtherOwner() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["JIBUNKIT_STORE_ACCESS_PROBE"] = "1"
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
            button.tap()
        }
        func status(_ value: String) {
            let text = app.staticTexts.matching(identifier: "store.access.status")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        func restore() {
            tap("runtime.restore.open")
            let selection = app.switches["backup.restore.lifecycle-a"]
            XCTAssertTrue(selection.waitForExistence(timeout: 10))
            selection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            tap("backup.restore")
            app.alerts.buttons["置き換えて復元"].tap()
        }
        for owner in ["lifecycle-b", "lifecycle-a"] {
            tap("miniapp.\(owner)")
            tap("store.access.start")
            status("running")
            if owner == "lifecycle-b" { app.navigationBars.buttons["ミニアプリ"].tap() }
        }
        restore()
        let conflict = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "lifecycle-aはデータを使用中です。")).firstMatch
        XCTAssertTrue(conflict.waitForExistence(timeout: 10), app.debugDescription)
        tap("閉じる")
        status("running")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "original")
        tap("store.access.finish")
        status("completed")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "written")
        restore()
        XCTAssertTrue(app.staticTexts["lifecycle-aを復元しました。"].waitForExistence(timeout: 10), app.debugDescription)
        tap("閉じる")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "restored")
        // A accepts a fresh ordinary operation after the restore's runtime restart.
        tap("store.access.start")
        status("running")
        tap("store.access.finish")
        status("completed")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        status("running")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "original")
        tap("store.access.finish")
        status("completed")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "written")
    }

    func testSelectedRestoreStopsAndRestartsOnlyItsRuntime() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func status(_ value: String) {
            let text = app.staticTexts.matching(identifier: "lifecycle.task.status")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            tap("miniapp.\(owner)")
            tap("lifecycle.task.start")
            status("running")
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        tap("miniapp.lifecycle-a")
        tap("runtime.restore.open")
        let selection = app.switches["backup.restore.lifecycle-a"]
        XCTAssertTrue(selection.waitForExistence(timeout: 10))
        selection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        tap("backup.restore")
        app.alerts.buttons["置き換えて復元"].tap()
        XCTAssertTrue(app.staticTexts["lifecycle-aを復元しました。"].waitForExistence(timeout: 10), app.debugDescription)
        tap("閉じる")
        status("idle")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "restored")
        tap("lifecycle.task.start")
        status("running")
        tap("lifecycle.task.complete")
        status("completed")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        status("running")
        XCTAssertEqual(app.staticTexts["runtime.restored.value"].label, "original")
        tap("lifecycle.task.complete")
        status("completed")
    }

    func testIdleTimerKeepsOtherFeaturesRequestActive() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ value: String) {
            let result = app.staticTexts.matching(identifier: "idle.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("idle.open")
        }
        func backToList() {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("idle.acquire")
            expect("disabled")
            backToList()
        }
        open("lifecycle-a")
        tap("idle.shutdown")
        expect("disabled")
        backToList()
        open("lifecycle-b")
        tap("idle.read")
        expect("disabled")
        tap("idle.shutdown")
        expect("enabled")
    }

    func testWebDataPersistsAndClearingPreservesOtherFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ value: String) {
            let result = app.staticTexts.matching(identifier: "webdata.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
            print("WEB-PERSISTENCE expected=\(value) \(app.staticTexts["webdata.diagnostic"].label)")
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("webdata.open")
            XCTAssertTrue(app.staticTexts["page-ready"].waitForExistence(timeout: 15), app.debugDescription)
        }
        // Restart between owners also verifies native persistence, not in-memory state.
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("webdata.remove")
            expect("removed")
            tap("webdata.save")
            expect("saved")
            tap("webdata.read")
            expect(owner)
            // Exercise the normal background lifecycle before process recreation.
            // Abrupt termination immediately after setCookie is a separate durability case.
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.terminate()
            app.launch()
        }
        open("lifecycle-a")
        tap("webdata.read")
        expect("lifecycle-a")
        tap("webdata.remove")
        expect("removed")
        tap("webdata.read")
        expect("missing")
        app.terminate()
        app.launch()
        open("lifecycle-b")
        tap("webdata.read")
        expect("lifecycle-b")
        tap("webdata.remove")
        expect("removed")
    }

    func testKeychainPersistsAndLogoutPreservesOtherFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ value: String) {
            let result = app.staticTexts.matching(identifier: "keychain.result")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
        }
        func open(_ owner: String) {
            tap("miniapp.\(owner)")
            tap("keychain.open")
        }
        // Restart between owners also verifies native persistence, not in-memory state.
        for owner in ["lifecycle-a", "lifecycle-b"] {
            open(owner)
            tap("keychain.remove")
            expect("removed")
            tap("keychain.save")
            expect("saved")
            app.terminate()
            app.launch()
        }
        open("lifecycle-a")
        tap("keychain.read")
        expect("lifecycle-a")
        tap("keychain.remove")
        expect("removed")
        tap("keychain.read")
        expect("missing")
        app.terminate()
        app.launch()
        open("lifecycle-b")
        tap("keychain.read")
        expect("lifecycle-b")
        tap("keychain.remove")
        expect("removed")
    }

    private func verifyNativeCustomActionReachesOwnerWithoutReplacingVisibleFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        tap("miniapp.lifecycle-a")
        tap("notification.action.schedule")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["scheduled"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7)))
        let card = springboard.buttons.matching(identifier: "ShortLook.Platter.Content.Seamless")
            .containing(.staticText, identifier: "Action-lifecycle-a").firstMatch
        let visible = card.waitForExistence(timeout: 20)
        let evidence = XCTAttachment(screenshot: springboard.screenshot())
        evidence.name = "custom-action-notification-center"
        evidence.lifetime = .keepAlways
        add(evidence)
        guard visible else {
            XCTFail("Action notification missing: \(springboard.debugDescription)")
            return
        }
        card.swipeLeft()
        let view = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["View", "表示"])).firstMatch
        guard view.waitForExistence(timeout: 5) else {
            let evidence = XCTAttachment(screenshot: springboard.screenshot())
            evidence.name = "custom-action-swiped"
            evidence.lifetime = .keepAlways
            add(evidence)
            XCTFail("Notification View action unavailable: \(springboard.debugDescription)")
            return
        }
        view.tap()
        let expanded = XCTAttachment(screenshot: springboard.screenshot())
        expanded.name = "custom-action-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        let action = springboard.buttons["Action"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), springboard.debugDescription)
        action.tap()
        app.activate()
        XCTAssertTrue(app.navigationBars["lifecycle-b"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["notification.action.result"].label, "none")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-a")
        let result = app.staticTexts.matching(identifier: "notification.action.result")
            .matching(NSPredicate(format: "label == %@", "same-action")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), app.debugDescription)
    }

    private func verifyForegroundNotificationsConsultOnlyTheirOwner() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func count(_ value: String) {
            let text = app.staticTexts.matching(identifier: "notification.foreground.count")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 15), app.debugDescription)
        }
        for owner in ["lifecycle-a", "lifecycle-b"] {
            tap("miniapp.\(owner)")
            count("0")
            tap("notification.schedule")
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            count("1")
            // Do not leave B's list notification to group with the later action probe.
            tap("notification.clear")
            XCTAssertTrue(app.staticTexts["cleared"].waitForExistence(timeout: 5))
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        tap("miniapp.lifecycle-a")
        count("1")
    }

    func testNativeCategoryUpdatesPreserveOtherFeature() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func expect(_ identifiers: [String]) {
            let text = app.staticTexts.matching(identifier: "notification.categories")
                .matching(NSPredicate(format: "label == %@", identifiers.sorted().joined(separator: ","))).firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 10), app.debugDescription)
        }
        let a = "jibunkit.lifecycle-a.category.aW5pdGlhbA=="
        let b = "jibunkit.lifecycle-b.category.aW5pdGlhbA=="
        let updated = "jibunkit.lifecycle-a.category.dXBkYXRlZA=="
        tap("miniapp.lifecycle-a")
        tap("notification.read")
        expect([a, b])
        tap("notification.replace")
        expect([updated, b])
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        tap("notification.read")
        expect([updated, b])
        tap("notification.remove")
        expect([updated])
        app.terminate()
        app.launch()
        tap("miniapp.lifecycle-a")
        tap("notification.read")
        expect([a, b])
    }

    func testCancellingOneFeatureLeavesOtherFeatureTaskRunning() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ id: String) {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
        }
        func status(_ value: String) {
            let expected = app.staticTexts.matching(identifier: "lifecycle.task.status")
                .matching(NSPredicate(format: "label == %@", value)).firstMatch
            XCTAssertTrue(expected.waitForExistence(timeout: 5))
        }
        for id in ["lifecycle-a", "lifecycle-b"] {
            tap("miniapp.\(id)")
            tap("lifecycle.task.start")
            status("running")
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        tap("miniapp.lifecycle-a")
        tap("lifecycle.task.cancel")
        status("cancelled")
        app.navigationBars.buttons["ミニアプリ"].tap()
        tap("miniapp.lifecycle-b")
        status("running")
        tap("lifecycle.task.complete")
        status("completed")
    }

    func testUnopenedFeaturesReceiveHostBackgroundAndResume() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["miniapp.lifecycle-a"].waitForExistence(timeout: 10))
        // Neither Feature's root view has been created yet.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        var observed: [String] = []
        for id in ["lifecycle-a", "lifecycle-b"] {
            let entry = app.buttons["miniapp.\(id)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            entry.tap()
            let events = app.staticTexts["lifecycle.events"]
            XCTAssertTrue(events.waitForExistence(timeout: 5))
            let phases = events.label.split(separator: ",")
            XCTAssertTrue(phases.contains("background"))
            XCTAssertGreaterThanOrEqual(phases.filter { $0 == "active" }.count, 2)
            observed.append(events.label)
            app.navigationBars.buttons["ミニアプリ"].tap()
        }
        XCTAssertEqual(observed.first, observed.last)
    }

    func testRecordReminderSchedulingAndCancellation() {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
        }
        tap(app.buttons["miniapp.records"])
        tap(app.buttons["records.add"])
        let title = "Notification-" + UUID().uuidString.prefix(8)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.buttons["records.save"])
        tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                            "records.row.", String(title))).firstMatch)
        app.swipeUp()
        tap(app.buttons["records.reminder.schedule"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["許可", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.staticTexts["通知を予約しました。"].waitForExistence(timeout: 10))
        tap(app.buttons["records.reminder.cancel"])
        XCTAssertTrue(app.staticTexts["この記録の通知を取り消しました。"].waitForExistence(timeout: 10))
    }

    func testRecordsUsesIndependentHostStorage() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
        }
        tap(app.buttons["miniapp.counter"])
        let counterValue = app.staticTexts["counter.value"].label
        tap(app.navigationBars.buttons["ミニアプリ"])
        tap(app.buttons["miniapp.records"])
        tap(app.buttons["records.add"])
        let title = "Hosted-" + UUID().uuidString.prefix(8)
        tap(app.textFields["records.title"])
        app.textFields["records.title"].typeText(String(title))
        tap(app.textViews["records.editor.body"])
        app.textViews["records.editor.body"].typeText("Host record")
        tap(app.buttons["records.save"])
        app.terminate()
        app.launch()
        tap(app.buttons["miniapp.records"])
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "records.row.", String(title))).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let recordID = String(row.identifier.dropFirst("records.row.".count))
        XCTAssertNotNil(UUID(uuidString: recordID))
        tap(row)
        XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["records.body"].label, "Host record")
        tap(app.navigationBars.buttons["記録"])
        tap(app.navigationBars.buttons["ミニアプリ"])
        tap(app.buttons["miniapp.counter"])
        XCTAssertEqual(app.staticTexts["counter.value"].label, counterValue)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/records?destination=invalid")))
        XCTAssertTrue(app.staticTexts["counter.value"].exists)
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/records?destination=\(recordID)")))
        XCTAssertTrue(app.staticTexts["records.body"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["records.body"].label, "Host record")
    }

    func testGeneratedFeatureCoexistsAndRoutesInHost() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let notes = app.buttons["miniapp.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["miniapp.counter"].exists)
        XCTAssertTrue(app.buttons["miniapp.reminder"].exists)
        notes.tap()
        XCTAssertTrue(app.staticTexts["Notes"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["ミニアプリ"].tap()
        let counter = app.buttons["miniapp.counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        counter.tap()
        XCTAssertTrue(app.staticTexts["counter.value"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/notes")))
        XCTAssertTrue(app.staticTexts["Notes"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["counter.value"].exists)
        app.navigationBars.buttons["ミニアプリ"].tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
    }
}
