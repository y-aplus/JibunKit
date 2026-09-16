import JibunKitCore
import SwiftUI

/// Diagnostic composition: production Features use the same public coordinator,
/// while the ordinary host remains unaware of camera/audio implementation details.
@MainActor
enum MediaIntegrationProbe {
    static let bridge = MediaCaptureAudioBridge(audio: MiniAppNativeAudio.coordinator)

    static var definitions: [MiniAppDefinition] {
        MediaCaptureProbe.makeAcquireAudio = { owner, stopNativeOnly in
            {
                let capture = MediaCaptureFixtures.photo.owner
                let generation = capture.operationGeneration
                return try await bridge.acquire(owner: owner, stopNativeOnly: stopNativeOnly,
                    released: {
                        // A lease can also be removed by another Feature's explicit
                        // switch. Close the remaining camera ownership afterwards.
                        Task { @MainActor in
                            if let generation {
                                await capture.suspend(.interrupted("音声の利用終了"), ifGeneration: generation)
                            }
                        }
                    })
            }
        }
        return MediaAudioProbe.definitions + MediaCaptureProbe.definitions + [
            MiniAppDefinition(id: MiniAppID("media-session"), title: "メディア調停", systemImage: "waveform") { _ in
                MediaSessionProbeView(bridge: bridge)
            },
        ]
    }
}

@MainActor
final class MediaCaptureAudioBridge: ObservableObject {
    enum Failure: Error { case conflict(String) }
    let audio: MiniAppAudioSessionCoordinator
    @Published var status = "音声付き撮影は再生・録音と同じ調停を使います。"
    @Published var replaceOnNextRequest = false

    init(audio: MiniAppAudioSessionCoordinator) { self.audio = audio }

    func acquire(owner: MiniAppID, stopNativeOnly: @escaping @MainActor @Sendable () async -> Void,
                 released: @escaping @MainActor @Sendable () -> Void) async throws
        -> (@MainActor @Sendable () async -> Void) {
        let replace = replaceOnNextRequest
        replaceOnNextRequest = false
        let request = MiniAppAudioRequest(acceptableProfiles: [
            .init(category: .playAndRecord, mode: .videoRecording),
            .init(category: .playAndRecord, mode: .spokenAudio),
        ], purpose: "音声付き動画", allowsInterruptionResume: false)
        let admission = try await audio.acquire(owner: owner, request: request,
            stop: { await stopNativeOnly() }, receive: { event in
                if case .released = event { released() }
            })
        let lease: MiniAppAudioSessionCoordinator.Lease
        switch admission {
        case .acquired(let acquired): lease = acquired
        case .conflict(let conflict):
            status = "音声競合: " + conflict.incumbentOwners.map(\.rawValue).sorted().joined(separator: ", ")
            guard replace else { throw Failure.conflict(status) }
            lease = try await audio.resolve(conflict, as: .replaceOwners(conflict.incumbentOwners))
        }
        status = "音声取得: \(owner.rawValue)"
        return { [self] in
            do {
                try await audio.release(lease)
                status = "音声解放: \(owner.rawValue)"
            } catch MiniAppAudioSessionCoordinator.Failure.unknownLease {
                // Explicit replacement already stopped and removed this lease.
            } catch {
                status = "音声解放失敗: \(error)。音声復旧を実行してください。"
                await audio.waitForRelease(lease)
            }
        }
    }

    func recover() async {
        do { try await audio.recoverSession(); status = "音声復旧済み" }
        catch { status = "音声復旧失敗: \(error)" }
    }
}

private struct MediaSessionProbeView: View {
    @ObservedObject var bridge: MediaCaptureAudioBridge
    var body: some View {
        Form {
            Text(bridge.status).textSelection(.enabled)
            Toggle("次の撮影で音声が競合したら相手を停止", isOn: $bridge.replaceOnNextRequest)
            Text("この指定は次の撮影で一度だけ使います。互換構成で動く相手は停止しません。")
            Button("音声復旧") { Task { await bridge.recover() } }
        }
    }
}
