#if os(iOS)
import JibunKitCore
import SwiftUI

@MainActor
struct MediaAudioProbeView: View {
    @Bindable var state: MediaAudioProbeState
    let recorder: Bool
    @Environment(\.miniAppConsentStore) private var consentStore

    private var microphoneConsent: Bool {
        consentStore?.consent(for: MiniAppID("media-audio-recorder"), permissionID: "microphone") == .allowed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(recorder ? state.recorderStatus : state.playerStatus).accessibilityIdentifier("media-audio.status")
                Text(state.detail).accessibilityIdentifier("media-audio.detail")
                Text(state.sceneSummary).accessibilityIdentifier("media-audio.scene")
                let error = recorder ? state.recorderError : state.playerError
                Text(error).foregroundStyle(error == "なし" ? .secondary : .red)
                    .accessibilityIdentifier("media-audio.error")
                if recorder {
                    Text(microphoneConsent ? "Feature microphone同意済み" : "管理画面でFeature microphone同意が必要")
                    Button("録音開始") { Task { await state.startRecording(featureConsent: microphoneConsent) } }
                    .accessibilityIdentifier("media-audio.record")
                Button("競合相手を停止して録音") { Task { await state.confirmRecorderReplacement(featureConsent: microphoneConsent) } }
                    .accessibilityIdentifier("media-audio.confirm-replace")
                    Button("録音停止して再生") { Task { await state.stopRecordingAndPlay() } }
                        .accessibilityIdentifier("media-audio.record-play")
                    Button("録音資源を解放") { Task { await state.releaseRecorder() } }
                        .accessibilityIdentifier("media-audio.stop-recorder")
                } else {
                    Button("ローカル音声を再生") { Task { await state.startPlayer() } }
                        .accessibilityIdentifier("media-audio.play")
                    Button("ユーザー停止") { Task { await state.stopPlayer() } }
                        .accessibilityIdentifier("media-audio.stop-player")
                }
            }.padding()
        }
    }
}
#endif
