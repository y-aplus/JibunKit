#if os(iOS)
import CoreLocation
import Foundation

/// Direct Core Location adapter. Each continuous update generation gets its own
/// manager, while a distinct manager reconnects the app-wide monitored regions.
@MainActor
public final class MiniAppCoreLocationClient: NSObject, MiniAppLocationNativeClient, CLLocationManagerDelegate {
    public var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)?
    private let regionManager: CLLocationManager
    private var updateManagers: [ObjectIdentifier: (CLLocationManager, UUID)] = [:]

    public override init() {
        regionManager = CLLocationManager()
        super.init()
        regionManager.delegate = self
    }

    public var authorization: MiniAppLocationAuthorization { Self.authorization(regionManager.authorizationStatus) }
    public var monitoredRegionIDs: Set<String> { Set(regionManager.monitoredRegions.map(\.identifier)) }
    public var isRegionMonitoringAvailable: Bool { CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) }

    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) {
        switch request {
        case .whenInUse: regionManager.requestWhenInUseAuthorization()
        case .always: regionManager.requestAlwaysAuthorization()
        }
    }

    public func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID) {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = configuration.desiredAccuracy
        manager.distanceFilter = configuration.distanceFilter
        manager.activityType = Self.activity(configuration.activityType)
        manager.pausesLocationUpdatesAutomatically = configuration.pausesAutomatically
        manager.allowsBackgroundLocationUpdates = configuration.background
        manager.showsBackgroundLocationIndicator = configuration.showsBackgroundIndicator
        updateManagers[ObjectIdentifier(manager)] = (manager, generation)
        manager.startUpdatingLocation()
    }

    public func stopUpdates(generation: UUID) {
        guard let entry = updateManagers.first(where: { $0.value.1 == generation }) else { return }
        entry.value.0.stopUpdatingLocation()
        entry.value.0.delegate = nil
        updateManagers.removeValue(forKey: entry.key)
    }

    public func startMonitoring(_ registration: MiniAppLocationRegistration) {
        let region: CLRegion
        switch registration.region {
        case .geofence(let latitude, let longitude, let radius, let entry, let exit):
            let circular = CLCircularRegion(center: .init(latitude: latitude, longitude: longitude),
                                            radius: min(radius, regionManager.maximumRegionMonitoringDistance),
                                            identifier: registration.id)
            circular.notifyOnEntry = entry; circular.notifyOnExit = exit
            region = circular
        case .beacon(let uuid, let major, let minor, let entry, let exit):
            let beacon: CLBeaconRegion
            if let major, let minor { beacon = CLBeaconRegion(uuid: uuid, major: major, minor: minor, identifier: registration.id) }
            else if let major { beacon = CLBeaconRegion(uuid: uuid, major: major, identifier: registration.id) }
            else { beacon = CLBeaconRegion(uuid: uuid, identifier: registration.id) }
            beacon.notifyOnEntry = entry; beacon.notifyOnExit = exit
            region = beacon
        }
        regionManager.startMonitoring(for: region)
    }

    public func stopMonitoring(identifier: String) {
        guard let region = regionManager.monitoredRegions.first(where: { $0.identifier == identifier }) else { return }
        regionManager.stopMonitoring(for: region)
    }

    public func requestState(identifier: String) {
        guard let region = regionManager.monitoredRegions.first(where: { $0.identifier == identifier }) else { return }
        regionManager.requestState(for: region)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        eventHandler?(.authorizationChanged(Self.authorization(manager.authorizationStatus)))
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let generation = updateManagers[ObjectIdentifier(manager)]?.1 else { return }
        eventHandler?(.locations(generation: generation, locations.map {
            .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                  horizontalAccuracy: $0.horizontalAccuracy, timestamp: $0.timestamp)
        }))
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard manager === regionManager else { return }; eventHandler?(.entered(identifier: region.identifier))
    }
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard manager === regionManager else { return }; eventHandler?(.exited(identifier: region.identifier))
    }
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard manager === regionManager else { return }
        let value: MiniAppLocationRegionState = state == .inside ? .inside : state == .outside ? .outside : .unknown
        eventHandler?(.state(identifier: region.identifier, value))
    }
    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        eventHandler?(.monitoringFailed(identifier: region?.identifier, message: error.localizedDescription))
    }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        eventHandler?(.failed(generation: updateManagers[ObjectIdentifier(manager)]?.1, message: error.localizedDescription))
    }

    private static func authorization(_ status: CLAuthorizationStatus) -> MiniAppLocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .denied
        }
    }
    private static func activity(_ value: MiniAppLocationActivity) -> CLActivityType {
        switch value {
        case .other: .other
        case .automotiveNavigation: .automotiveNavigation
        case .fitness: .fitness
        case .otherNavigation: .otherNavigation
        case .airborne: .airborne
        }
    }
}
#else
import Foundation

@MainActor
public final class MiniAppCoreLocationClient: MiniAppLocationNativeClient {
    public init() {}
    public var authorization: MiniAppLocationAuthorization { .denied }
    public var monitoredRegionIDs: Set<String> { [] }
    public var isRegionMonitoringAvailable: Bool { false }
    public var eventHandler: (@MainActor @Sendable (MiniAppLocationNativeEvent) -> Void)?
    public func requestAuthorization(_ request: MiniAppLocationAuthorizationRequest) {}
    public func startUpdates(configuration: MiniAppLocationUpdateConfiguration, generation: UUID) {}
    public func stopUpdates(generation: UUID) {}
    public func startMonitoring(_ registration: MiniAppLocationRegistration) {}
    public func stopMonitoring(identifier: String) {}
    public func requestState(identifier: String) {}
}
#endif
