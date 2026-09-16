#if os(iOS)
import AVFAudio
import Foundation

@MainActor
public final class MiniAppNativeAudioSessionDriver: MiniAppAudioSessionDriver {
    private let session: AVAudioSession
    private weak var coordinator: MiniAppAudioSessionCoordinator?
    private let observations = MiniAppNotificationObservations()

    /// Use one default instance per process. The injectable session exists for native tests.
    public init(session: AVAudioSession = .sharedInstance()) { self.session = session }

    public func connect(to coordinator: MiniAppAudioSessionCoordinator,
                        center: NotificationCenter = .default) throws {
        precondition(self.coordinator == nil, "A native audio driver connects to one coordinator.")
        self.coordinator = coordinator
        try observations.observe(center: center, name: AVAudioSession.interruptionNotification,
                                 object: session, extract: { note -> (UInt, UInt)? in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return nil }
            return (type, note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        }, receive: { [weak self] typeAndOptions in
            guard let type = AVAudioSession.InterruptionType(rawValue: typeAndOptions.0) else { return }
                if type == .began { self?.coordinator?.receiveInterruptionBegan() }
                else {
                    self?.coordinator?.receiveInterruptionEnded(
                        shouldResume: AVAudioSession.InterruptionOptions(rawValue: typeAndOptions.1).contains(.shouldResume)
                    )
                }
        })
        try observations.observe(center: center, name: AVAudioSession.routeChangeNotification,
                                 object: session, extract: {
            $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        }, receive: { [weak self] reason in self?.coordinator?.receiveRouteChange(reason: reason) })
        try observations.observe(center: center, name: AVAudioSession.mediaServicesWereResetNotification,
                                 object: session, extract: { _ in true },
                                 receive: { [weak self] _ in self?.coordinator?.receiveMediaServicesReset() })
    }

    public func apply(_ profile: MiniAppAudioProfile) throws {
        guard let policy = AVAudioSession.RouteSharingPolicy(rawValue: profile.policy.rawValue) else {
            throw NativeFailure.unsupportedRouteSharingPolicy(profile.policy.rawValue)
        }
        try session.setCategory(.init(rawValue: profile.category.rawValue),
                                mode: .init(rawValue: profile.mode.rawValue), policy: policy,
                                options: .init(rawValue: profile.options.rawValue))
    }

    public func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        try session.setActive(active, options: active || !notifyOthersOnDeactivation ? [] : .notifyOthersOnDeactivation)
    }

    private enum NativeFailure: Error { case unsupportedRouteSharingPolicy(UInt) }
}

/// The one production AVAudioSession owner. Feature and Capture bridges share this coordinator.
@MainActor
public enum MiniAppNativeAudio {
    private static let driver = MiniAppNativeAudioSessionDriver()
    public static let coordinator: MiniAppAudioSessionCoordinator = {
        let value = MiniAppAudioSessionCoordinator(driver: driver)
        try! driver.connect(to: value)
        return value
    }()
}
#endif
