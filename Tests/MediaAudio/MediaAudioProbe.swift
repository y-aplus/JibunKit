// Copied into the generated signed host app by the parent integration.
#if os(iOS)
import JibunKitCore
import SwiftUI

@MainActor
enum MediaAudioProbe {
    static let state = MediaAudioProbeState()
    static let playerLifetime = MiniAppFeatureLifetime(id: MiniAppID("media-audio-player")) { runtime in
        try runtime.onShutdownAsync { await state.stopPlayer() }
    }
    static let recorderLifetime = MiniAppFeatureLifetime(id: MiniAppID("media-audio-recorder")) { runtime in
        try runtime.onShutdownAsync { await state.releaseRecorder() }
    }

    static var definitions: [MiniAppDefinition] {
        [
            MiniAppDefinition(id: playerLifetime.id, title: "Audio Player", systemImage: "play.circle",
                              lifetime: playerLifetime,
                              onSceneActivityChange: state.receiveSceneActivity) { _ in
                MediaAudioProbeView(state: state, recorder: false)
            },
            MiniAppDefinition(id: recorderLifetime.id, title: "Audio Recorder", systemImage: "mic.circle",
                              lifetime: recorderLifetime,
                              permissions: [.init(id: "microphone", title: "マイク", purpose: "音声を録音します", deniedBehavior: "録音は開始しません")],
                              onSceneActivityChange: state.receiveSceneActivity) { _ in
                MediaAudioProbeView(state: state, recorder: true)
            },
        ]
    }
}
#endif
