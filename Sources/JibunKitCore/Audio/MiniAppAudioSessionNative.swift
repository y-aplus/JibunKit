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
        try session.setCategory(category(profile.category), mode: mode(profile.mode),
                                policy: policy(profile.policy), options: options(profile.options))
    }

    public func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws {
        try session.setActive(active, options: active || !notifyOthersOnDeactivation ? [] : .notifyOthersOnDeactivation)
    }

    private func category(_ value: MiniAppAudioProfile.Category) -> AVAudioSession.Category {
        switch value {
        case .ambient: .ambient
        case .soloAmbient: .soloAmbient
        case .playback: .playback
        case .record: .record
        case .playAndRecord: .playAndRecord
        case .multiRoute: .multiRoute
        }
    }

    private func mode(_ value: MiniAppAudioProfile.Mode) -> AVAudioSession.Mode {
        switch value {
        case .default: .default
        case .voiceChat: .voiceChat
        case .gameChat: .gameChat
        case .videoRecording: .videoRecording
        case .measurement: .measurement
        case .moviePlayback: .moviePlayback
        case .videoChat: .videoChat
        case .spokenAudio: .spokenAudio
        }
    }

    private func policy(_ value: MiniAppAudioProfile.RouteSharingPolicy) -> AVAudioSession.RouteSharingPolicy {
        switch value {
        case .default: .default
        case .longFormAudio: .longFormAudio
        case .longFormVideo: .longFormVideo
        case .independent: .independent
        }
    }

    private func options(_ value: MiniAppAudioProfile.Options) -> AVAudioSession.CategoryOptions {
        var result: AVAudioSession.CategoryOptions = []
        if value.contains(.mixWithOthers) { result.insert(.mixWithOthers) }
        if value.contains(.duckOthers) { result.insert(.duckOthers) }
        if value.contains(.interruptSpokenAudioAndMixWithOthers) { result.insert(.interruptSpokenAudioAndMixWithOthers) }
        if value.contains(.allowBluetoothHFP) { result.insert(.allowBluetoothHFP) }
        if value.contains(.allowBluetoothA2DP) { result.insert(.allowBluetoothA2DP) }
        if value.contains(.allowAirPlay) { result.insert(.allowAirPlay) }
        if value.contains(.defaultToSpeaker) { result.insert(.defaultToSpeaker) }
        return result
    }
}
#endif
