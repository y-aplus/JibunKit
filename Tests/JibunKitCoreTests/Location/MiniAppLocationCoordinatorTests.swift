import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppLocationCoordinatorTests: XCTestCase {
    func testFeatureConsentPrecedesOSPromptAndNativeWork() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        XCTAssertThrowsError(try coordinator.requestAuthorization(owner: MiniAppID("a"), featureConsent: false, request: .always)) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .featureConsentDenied)
        }
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "home", region: fence(), featureConsent: false))
        XCTAssertTrue(native.actions.isEmpty)
    }

    func testTwoOwnersWithSameLocalIDReceiveOnlyTheirRegistration() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = LocationEvents(), b = LocationEvents()
        coordinator.connect(owner: MiniAppID("a")) { a.values.append($0) }
        coordinator.connect(owner: MiniAppID("b")) { b.values.append($0) }
        let ar = try coordinator.register(owner: MiniAppID("a"), localID: "same", region: fence(), featureConsent: true)
        let br = try coordinator.register(owner: MiniAppID("b"), localID: "same", region: fence(), featureConsent: true)
        native.send(.entered(identifier: ar.id)); native.send(.exited(identifier: br.id))
        XCTAssertEqual(a.values, [.entered(ar)]); XCTAssertEqual(b.values, [.exited(br)])
        XCTAssertNotEqual(ar.id, br.id)
    }

    func testOwnerUnregisterPreservesOtherOwnerAndUnknownNativeRegion() throws {
        let native = LocationNative(); native.authorization = .always
        native.ids = ["host-owned"]
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = try coordinator.register(owner: MiniAppID("a"), localID: "a", region: fence(), featureConsent: true)
        let b = try coordinator.register(owner: MiniAppID("b"), localID: "b", region: fence(), featureConsent: true)
        try coordinator.unregisterAll(owner: MiniAppID("a"))
        XCTAssertTrue(native.ids.contains("host-owned")); XCTAssertFalse(native.ids.contains(a.id)); XCTAssertTrue(native.ids.contains(b.id))
    }

    func testSharedTwentyRegionLimitIncludesUnknownNativeRegistrations() throws {
        let native = LocationNative(); native.authorization = .always
        native.ids = Set((0..<20).map { "external-\($0)" })
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "overflow", region: fence(), featureConsent: true)) {
            XCTAssertEqual($0 as? MiniAppLocationFailure, .capacityExceeded(limit: 20, occupied: 20))
        }
        XCTAssertEqual(native.ids.count, 20)
    }

    func testFailedPersistenceRollsBackReservationBeforeNativeStart() {
        let native = LocationNative(); native.authorization = .always
        let store = LocationStore(); store.writeError = StoreError.failed
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        XCTAssertThrowsError(try coordinator.register(owner: MiniAppID("a"), localID: "x", region: fence(), featureConsent: true))
        XCTAssertTrue(coordinator.allRegistrations.isEmpty); XCTAssertTrue(native.ids.isEmpty)
    }

    func testLateUpdateFromStoppedGenerationIsDropped() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let events = LocationEvents()
        coordinator.connect(owner: MiniAppID("a")) { events.values.append($0) }
        let generation = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true,
            configuration: .init(desiredAccuracy: 10))
        try coordinator.stopUpdates(owner: MiniAppID("a"), generation: generation)
        native.send(.locations(generation: generation, [.init(latitude: 1, longitude: 2, horizontalAccuracy: 3, timestamp: .distantPast)]))
        XCTAssertTrue(events.values.isEmpty)
    }

    func testPersistedRegionsReconnectWithoutRestartingContinuousUpdates() throws {
        let native = LocationNative(); native.authorization = .always
        let persisted = try MiniAppLocationRegistration(owner: MiniAppID("a"), localID: "cold", region: fence())
        let store = LocationStore(); store.values = [persisted]
        let coordinator = MiniAppLocationCoordinator(native: native, store: store)
        coordinator.reconnectPersistedMonitoring()
        XCTAssertEqual(native.ids, [persisted.id])
        XCTAssertFalse(native.actions.contains(where: { $0.hasPrefix("updates:") }))
    }

    func testBackgroundAndForegroundPreserveConfigurationWithWhenInUse() throws {
        let native = LocationNative(); native.authorization = .whenInUse
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        _ = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true,
                                         configuration: .init(desiredAccuracy: 100, background: false))
        _ = try coordinator.startUpdates(owner: MiniAppID("b"), featureConsent: true,
                                         configuration: .init(desiredAccuracy: 5, background: true))
        XCTAssertEqual(native.actions.filter { $0.hasPrefix("updates:") }.count, 2)
    }

    func testAuthorizationRevocationStopsEveryUpdateButKeepsDurableRegions() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let registration = try coordinator.register(owner: MiniAppID("a"), localID: "durable", region: fence(), featureConsent: true)
        _ = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true, configuration: .init(desiredAccuracy: 10))
        _ = try coordinator.startUpdates(owner: MiniAppID("b"), featureConsent: true, configuration: .init(desiredAccuracy: 100))
        native.authorization = .denied; native.send(.authorizationChanged(.denied))
        XCTAssertEqual(native.actions.filter { $0.hasPrefix("stop-updates:") }.count, 2)
        XCTAssertEqual(coordinator.allRegistrations, [registration])
    }

    func testMonitoringFailureReleasesOwnedReservation() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let registration = try coordinator.register(owner: MiniAppID("a"), localID: "failed", region: fence(), featureConsent: true)
        native.send(.monitoringFailed(identifier: registration.id, message: "limit"))
        XCTAssertTrue(coordinator.allRegistrations.isEmpty)
    }

    func testFeatureConsentRevocationStopsAndRemovesOnlyThatOwner() throws {
        let native = LocationNative(); native.authorization = .always
        let coordinator = MiniAppLocationCoordinator(native: native, store: LocationStore())
        let a = try coordinator.register(owner: MiniAppID("a"), localID: "a", region: fence(), featureConsent: true)
        let b = try coordinator.register(owner: MiniAppID("b"), localID: "b", region: fence(), featureConsent: true)
        _ = try coordinator.startUpdates(owner: MiniAppID("a"), featureConsent: true, configuration: .init(desiredAccuracy: 10))
        try coordinator.revoke(owner: MiniAppID("a"))
        XCTAssertFalse(native.ids.contains(a.id)); XCTAssertTrue(native.ids.contains(b.id))
        XCTAssertEqual(coordinator.allRegistrations, [b])
        XCTAssertEqual(native.actions.filter { $0.hasPrefix("stop-updates:") }.count, 1)
    }
}

private func fence() -> MiniAppLocationRegion {
    .geofence(latitude: 35, longitude: 139, radius: 100, notifyOnEntry: true, notifyOnExit: true)
}

private enum StoreError: Error { case failed }
@MainActor private final class LocationEvents { var values: [MiniAppLocationEvent] = [] }
private final class LocationStore: MiniAppLocationRegistrationStore, @unchecked Sendable {
    var values: [MiniAppLocationRegistration] = []
    var writeError: Error?
    func read() throws -> [MiniAppLocationRegistration] { values }
    func write(_ registrations: [MiniAppLocationRegistration]) throws {
        if let writeError { throw writeError }; values = registrations
    }
}

@MainActor private final class LocationNative: MiniAppLocationNativeClient {
    var authorization: MiniAppLocationAuthorization = .notDetermined
    var ids: Set<String> = []
    var monitoredRegionIDs: Set<String> { ids }
    var isRegionMonitoringAvailable = true
    var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)?
    var actions: [String] = []
    func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) { actions.append("permission:\(request.rawValue)") }
    func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID) { actions.append("updates:\(generation)") }
    func stopUpdates(generation: UUID) { actions.append("stop-updates:\(generation)") }
    func startMonitoring(_ registration: MiniAppLocationRegistration) { ids.insert(registration.id); actions.append("monitor:\(registration.id)") }
    func stopMonitoring(identifier: String) { ids.remove(identifier); actions.append("stop:\(identifier)") }
    func requestState(identifier: String) { actions.append("state:\(identifier)") }
    func send(_ event: MiniAppLocationNativeEvent) { eventHandler?(event) }
}
