import XCTest

@MainActor
enum P1UIVisibility {
    static func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let management = app.collectionViews["management.list"]
        let inManagement = management.exists
        let list = inManagement ? management : app.collectionViews.firstMatch
        // Back/management/close controls belong to fixed navigation chrome,
        // not the scrollable List viewport. The stopped-runtime resume screen
        // has no List at all.
        if element.exists && element.isHittable {
            let frame = element.frame
            if app.navigationBars.allElementsBoundByIndex.contains(where: {
                $0.isHittable && $0.frame.contains(frame)
            }) { return }
        }
        if !list.exists {
            XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertTrue(element.isHittable && app.frame.contains(element.frame), app.debugDescription)
            return
        }
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)

        func position() -> Bool {
            guard element.exists else { return false }
            for _ in 0..<6 {
                guard element.exists else { return false }
                let frame = element.frame
                let bar = inManagement ? app.navigationBars["ミニアプリの管理"] : app.navigationBars.firstMatch
                let top = max(list.frame.minY, bar.frame.maxY) + 4
                let search = app.searchFields.firstMatch
                let bottom = !inManagement && search.exists && search.isHittable
                    ? search.frame.minY - 4 : min(list.frame.maxY, app.frame.maxY) - 30
                // isHittable alone accepts partially clipped rows. Their center
                // can still be outside the List or behind a toolbar when tapped.
                if frame.height > 0 && frame.minY >= top && frame.maxY <= bottom && element.isHittable {
                    return true
                }
                let startY = frame.minY < top ? 0.40 : 0.75
                let endY = frame.minY < top ? 0.70 : 0.40
                list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.05, thenDragTo:
                        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
            }
            return false
        }
        if position() { return }
        for _ in 0..<10 {
            list.swipeDown()
            if position() { return }
        }
        for _ in 0..<24 {
            list.swipeUp()
            if position() { return }
        }
        XCTFail("Could not fully reveal \(element.debugDescription)\n\(app.debugDescription)")
    }
}
