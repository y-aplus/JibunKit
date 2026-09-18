#if os(iOS)
import JibunKitCore
import SwiftUI
import UIKit
import XCTest
@testable import JibunKit_App

@MainActor
final class P2AppearanceNativeTests: XCTestCase, @unchecked Sendable {
    func testNormalDefinitionsDriveIndependentSceneIdleRequests() async throws {
        var nativeChanges: [Bool] = []
        let timer = MiniAppIdleTimer { nativeChanges.append($0) }
        let a = P2AppearanceFeature(id: MiniAppID("appearance-test-a"), title: "A", scheme: .dark, timer: timer)
        let b = P2AppearanceFeature(id: MiniAppID("appearance-test-b"), title: "B", scheme: .light, timer: timer)
        try await a.lifetime.start(); try await b.lifetime.start()
        let scenes = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: a.id, handler: a.receive), .init(id: b.id, handler: b.receive),
        ])
        scenes.connect(phase: .active, selectedID: a.id)
        a.setRequested(true); b.setRequested(true)
        XCTAssertTrue(a.requested && a.effective)
        XCTAssertTrue(b.requested && !b.effective)
        scenes.update(phase: .active, selectedID: b.id)
        a.refreshEffective(); b.refreshEffective()
        XCTAssertTrue(a.requested && !a.effective)
        XCTAssertTrue(b.requested && b.effective)
        scenes.update(phase: .background, selectedID: b.id)
        b.refreshEffective()
        XCTAssertFalse(b.effective)
        XCTAssertEqual(nativeChanges, [true, false, true, false])
        await a.lifetime.stop(); await b.lifetime.stop()
    }

    func testEnvironmentOverrideChangesSwiftUIReadingWithoutClaimingUIKitTrait() async {
        let feature = P2AppearanceFeature(id: MiniAppID("appearance-env"), title: "Environment", scheme: .dark)
        let host = UIHostingController(rootView: P2AppearanceRoot(feature: feature, policy: .environment(.dark)))
        let window = mount(host, style: .light)
        await settle()
        XCTAssertEqual(feature.rootEnvironment, "dark")
        XCTAssertEqual(window.traitCollection.userInterfaceStyle, .light)
        // The embedded UIKit trait is recorded separately; it is not assumed to
        // follow a SwiftUI environment override.
        XCTAssertNotEqual(feature.rootTrait, "unread")
        feature.showingSheet = true
        await settle()
        XCTAssertEqual(feature.sheetEnvironment, "dark")
        XCTAssertNotEqual(feature.sheetTrait, "closed")
    }

    func testPreferredSchemeAffectsItsPresentationButNotAnotherWindow() async {
        let a = P2AppearanceFeature(id: MiniAppID("appearance-preferred-a"), title: "A", scheme: .dark)
        let b = P2AppearanceFeature(id: MiniAppID("appearance-preferred-b"), title: "B", scheme: .light)
        let aHost = UIHostingController(rootView: P2AppearanceRoot(feature: a, policy: .preferred(.dark)))
        let bHost = UIHostingController(rootView: P2AppearanceRoot(feature: b, policy: .preferred(.light)))
        let aWindow = mount(aHost, style: .light)
        let bWindow = mount(bHost, style: .dark)
        await settle()
        XCTAssertEqual(a.rootEnvironment, "dark")
        XCTAssertEqual(b.rootEnvironment, "light")
        XCTAssertEqual(aHost.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(bHost.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(aWindow.rootViewController?.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(bWindow.rootViewController?.traitCollection.userInterfaceStyle, .light)
        a.showingSheet = true
        await settle()
        XCTAssertEqual(a.sheetEnvironment, "dark")
        XCTAssertEqual(a.sheetTrait, "dark")
        XCTAssertEqual(b.rootEnvironment, "light")
    }

    func testContainedUIKitControllerOverrideDoesNotChangeSiblingOrWindow() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = .light
        let parent = UIViewController()
        let dark = P2ContainedAppearanceViewController(style: .dark)
        let inherited = P2ContainedAppearanceViewController(style: .unspecified)
        parent.addChild(dark); parent.view.addSubview(dark.view); dark.didMove(toParent: parent)
        parent.addChild(inherited); parent.view.addSubview(inherited.view); inherited.didMove(toParent: parent)
        window.rootViewController = parent; window.makeKeyAndVisible(); parent.view.layoutIfNeeded()
        XCTAssertEqual(dark.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(inherited.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(window.traitCollection.userInterfaceStyle, .light)
    }

    private func mount<Content: View>(_ host: UIHostingController<Content>, style: UIUserInterfaceStyle) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return window
    }

    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
#endif
