import Foundation
import XCTest
import JibunKitCore

final class MiniAppConsentStoreTests: XCTestCase, @unchecked Sendable {
    func testPermissionDeclarationKeepsStableUserFacingContract() {
        let declaration = MiniAppPermissionDeclaration(
            id: "notifications.reminders",
            title: "Reminder notifications",
            purpose: "Notify you when a reminder is due.",
            deniedBehavior: "Reminders remain available without alerts."
        )

        XCTAssertEqual(declaration.id, "notifications.reminders")
        XCTAssertEqual(declaration.title, "Reminder notifications")
        XCTAssertEqual(declaration.purpose, "Notify you when a reminder is due.")
        XCTAssertEqual(declaration.deniedBehavior, "Reminders remain available without alerts.")
    }

    @MainActor
    func testDecisionsAreIndependentByFeatureAndPermissionAndSurviveRestart() throws {
        let fixture = try ConsentDefaultsFixture()
        defer { fixture.remove() }
        let first = MiniAppConsentStore(defaults: fixture.defaults)
        let featureA = MiniAppID("feature-a")
        let featureB = MiniAppID("feature-b")

        XCTAssertEqual(first.consent(for: featureA, permissionID: "camera"), .notDetermined)
        first.setConsent(.allowed, for: featureA, permissionID: "camera")
        first.setConsent(.denied, for: featureA, permissionID: "location")
        first.setConsent(.allowed, for: featureB, permissionID: "camera")

        let restarted = MiniAppConsentStore(defaults: fixture.defaults)
        XCTAssertEqual(restarted.consent(for: featureA, permissionID: "camera"), .allowed)
        XCTAssertEqual(restarted.consent(for: featureA, permissionID: "location"), .denied)
        XCTAssertEqual(restarted.consent(for: featureB, permissionID: "camera"), .allowed)
        XCTAssertEqual(restarted.consent(for: featureB, permissionID: "location"), .notDetermined)
    }

    @MainActor
    func testRemovingOwnConsentDoesNotChangeOtherOwnersOrPermissions() throws {
        let fixture = try ConsentDefaultsFixture()
        defer { fixture.remove() }
        let store = MiniAppConsentStore(defaults: fixture.defaults)
        let featureA = MiniAppID("feature-a")
        let featureB = MiniAppID("feature-b")
        store.setConsent(.allowed, for: featureA, permissionID: "camera")
        store.setConsent(.denied, for: featureA, permissionID: "location")
        store.setConsent(.allowed, for: featureB, permissionID: "camera")

        store.removeConsent(for: featureA, permissionID: "camera")
        XCTAssertEqual(store.consent(for: featureA, permissionID: "camera"), .notDetermined)
        XCTAssertEqual(store.consent(for: featureA, permissionID: "location"), .denied)
        XCTAssertEqual(store.consent(for: featureB, permissionID: "camera"), .allowed)

        store.removeConsents(for: featureA)
        let restarted = MiniAppConsentStore(defaults: fixture.defaults)
        XCTAssertEqual(restarted.consent(for: featureA, permissionID: "location"), .notDetermined)
        XCTAssertEqual(restarted.consent(for: featureB, permissionID: "camera"), .allowed)
    }

    @MainActor
    func testNotDeterminedAndMalformedOrUnknownSavedValuesAreSafe() throws {
        let fixture = try ConsentDefaultsFixture()
        defer { fixture.remove() }
        let storageKey = "test-consents"
        let feature = MiniAppID("feature-a")
        let store = MiniAppConsentStore(defaults: fixture.defaults, storageKey: storageKey)

        fixture.defaults.set(["not": 42], forKey: storageKey)
        XCTAssertEqual(store.consent(for: feature, permissionID: "camera"), .notDetermined)

        let encodedFeature = Data(feature.rawValue.utf8).base64EncodedString()
        let encodedPermission = Data("camera".utf8).base64EncodedString()
        fixture.defaults.set(
            [encodedFeature + "." + encodedPermission: "future-value"],
            forKey: storageKey
        )
        XCTAssertEqual(store.consent(for: feature, permissionID: "camera"), .notDetermined)

        store.setConsent(.denied, for: feature, permissionID: "camera")
        XCTAssertEqual(store.consent(for: feature, permissionID: "camera"), .denied)
        store.setConsent(.notDetermined, for: feature, permissionID: "camera")
        XCTAssertEqual(store.consent(for: feature, permissionID: "camera"), .notDetermined)
    }
}

private final class ConsentDefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "MiniAppConsentStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
