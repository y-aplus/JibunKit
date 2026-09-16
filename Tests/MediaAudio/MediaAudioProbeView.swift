#if os(iOS)
import SwiftUI

@MainActor
struct MediaAudioProbeView: View {
    @Bindable var state: MediaAudioProbeState
    let recorder: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(state.status).accessibilityIdentifier("media-audio.status")
                Text(state.detail).accessibilityIdentifier("media-audio.detail")
                Text(state.sceneSummary).accessibilityIdentifier("media-audio.scene")
                Text(state.errorText).foregroundStyle(state.errorText == "なし" ? .secondary : .red)
                    .accessibilityIdentifier("media-audio.error")
                if recorder {
                    Toggle("このFeatureのmicrophone利用に同意", isOn: Binding(
                        get: { state.microphoneConsent }, set: state.setMicrophoneConsent))
                Button("録音開始") { Task { await state.startRecording() } }
                    .accessibilityIdentifier("media-audio.record")
                Button("競合相手を停止して録音") { Task { await state.confirmRecorderReplacement() } }
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
