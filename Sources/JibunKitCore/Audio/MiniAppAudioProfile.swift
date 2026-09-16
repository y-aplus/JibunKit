import Foundation

public struct MiniAppAudioProfile: Hashable, Sendable {
    public struct Category: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Self(rawValue: "AVAudioSessionCategoryAmbient")
        public static let soloAmbient = Self(rawValue: "AVAudioSessionCategorySoloAmbient")
        public static let playback = Self(rawValue: "AVAudioSessionCategoryPlayback")
        public static let record = Self(rawValue: "AVAudioSessionCategoryRecord")
        public static let playAndRecord = Self(rawValue: "AVAudioSessionCategoryPlayAndRecord")
        public static let multiRoute = Self(rawValue: "AVAudioSessionCategoryMultiRoute")
    }
    public struct Mode: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Self(rawValue: "AVAudioSessionModeDefault")
        public static let voiceChat = Self(rawValue: "AVAudioSessionModeVoiceChat")
        public static let gameChat = Self(rawValue: "AVAudioSessionModeGameChat")
        public static let videoRecording = Self(rawValue: "AVAudioSessionModeVideoRecording")
        public static let measurement = Self(rawValue: "AVAudioSessionModeMeasurement")
        public static let moviePlayback = Self(rawValue: "AVAudioSessionModeMoviePlayback")
        public static let videoChat = Self(rawValue: "AVAudioSessionModeVideoChat")
        public static let spokenAudio = Self(rawValue: "AVAudioSessionModeSpokenAudio")
    }
    public struct RouteSharingPolicy: RawRepresentable, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let `default` = Self(rawValue: 0)
        public static let longFormAudio = Self(rawValue: 1)
        public static let longFormVideo = Self(rawValue: 2)
        public static let independent = Self(rawValue: 3)
    }
    /// AVAudioSession.CategoryOptions raw bits; unknown future bits survive unchanged.
    public struct Options: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = Self(rawValue: 1 << 0)
        public static let duckOthers = Self(rawValue: 1 << 1)
        public static let allowBluetoothHFP = Self(rawValue: 1 << 2)
        public static let defaultToSpeaker = Self(rawValue: 1 << 3)
        public static let interruptSpokenAudioAndMixWithOthers = Self(rawValue: 1 << 4)
        public static let allowBluetoothA2DP = Self(rawValue: 1 << 5)
        public static let allowAirPlay = Self(rawValue: 1 << 6)
    }

    public let category: Category
    public let mode: Mode
    public let policy: RouteSharingPolicy
    public let options: Options
    public init(category: Category, mode: Mode = .default,
                policy: RouteSharingPolicy = .default, options: Options = []) {
        self.category = category; self.mode = mode; self.policy = policy; self.options = options
    }
}

public struct MiniAppAudioRequest: Sendable {
    public let acceptableProfiles: [MiniAppAudioProfile]
    public let purpose: String
    public let allowsInterruptionResume: Bool
    public init(acceptableProfiles: [MiniAppAudioProfile], purpose: String,
                allowsInterruptionResume: Bool = true) {
        self.acceptableProfiles = acceptableProfiles; self.purpose = purpose
        self.allowsInterruptionResume = allowsInterruptionResume
    }
}

public enum MiniAppAudioIntent: Sendable, Equatable { case active, paused, stoppedByUser, stoppedForRouteChange }
public enum MiniAppAudioEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(resumeCandidate: Bool)
    case routeChanged(reason: UInt)
    case mediaServicesReset
}

@MainActor public protocol MiniAppAudioSessionDriver: AnyObject {
    func apply(_ profile: MiniAppAudioProfile) throws
    func setActive(_ active: Bool, notifyOthersOnDeactivation: Bool) throws
}
