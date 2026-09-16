import Foundation

public struct MiniAppAudioProfile: Hashable, Sendable {
    public enum Category: String, Hashable, Sendable {
        case ambient, soloAmbient, playback, record, playAndRecord, multiRoute
    }

    public enum Mode: String, Hashable, Sendable {
        case `default`, voiceChat, gameChat, videoRecording, measurement, moviePlayback, videoChat, spokenAudio
    }

    public enum RouteSharingPolicy: String, Hashable, Sendable {
        case `default`, longFormAudio, longFormVideo, independent
    }

    public struct Options: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let mixWithOthers = Self(rawValue: 1 << 0)
        public static let duckOthers = Self(rawValue: 1 << 1)
        public static let interruptSpokenAudioAndMixWithOthers = Self(rawValue: 1 << 2)
        public static let allowBluetoothHFP = Self(rawValue: 1 << 3)
        public static let allowBluetoothA2DP = Self(rawValue: 1 << 4)
        public static let allowAirPlay = Self(rawValue: 1 << 5)
        public static let defaultToSpeaker = Self(rawValue: 1 << 6)
    }

    public let category: Category
    public let mode: Mode
    public let policy: RouteSharingPolicy
    public let options: Options

    public init(category: Category, mode: Mode = .default,
                policy: RouteSharingPolicy = .default, options: Options = []) {
        self.category = category
        self.mode = mode
        self.policy = policy
        self.options = options
    }
}

public struct MiniAppAudioRequest: Sendable {
    public let acceptableProfiles: [MiniAppAudioProfile]
    public let purpose: String
    public let allowsInterruptionResume: Bool

    public init(acceptableProfiles: [MiniAppAudioProfile], purpose: String,
                allowsInterruptionResume: Bool = true) {
        self.acceptableProfiles = acceptableProfiles
        self.purpose = purpose
        self.allowsInterruptionResume = allowsInterruptionResume
    }
}

public enum MiniAppAudioIntent: Sendable, Equatable {
    case active
    case paused
    case stoppedByUser
    case stoppedForRouteChange
}

public enum MiniAppAudioEvent: Sendable, Equatable {
    case interruptionBegan
    /// A candidate only. The Feature still decides whether its producer can resume.
    case interruptionEnded(resumeCandidate: Bool)
    case routeChanged(reason: UInt)
    case mediaServicesReset
}

@MainActor
public protocol MiniAppAudioSessionDriver: AnyObject {
    func apply(_ profile: MiniAppAudioProfile) throws
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws
}
