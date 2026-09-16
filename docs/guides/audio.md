# AudioSession / Now Playing integration

`MiniAppAudioSessionCoordinator` は一つのhost processで一個を共有する。productionでは一個の`MiniAppNativeAudioSessionDriver`を作り、coordinatorへ注入して`connect(to:)`する。テストは独立driverを注入する。Featureはplayer/recorder、録音物、再生位置、再開判断を所有し、coordinatorは`AVAudioSession`構成だけを所有する。

```swift
let driver = MiniAppNativeAudioSessionDriver()
let audio = MiniAppAudioSessionCoordinator(driver: driver)
try driver.connect(to: audio)

let admission = try await audio.acquire(
    owner: id,
    request: MiniAppAudioRequest(
        acceptableProfiles: [.init(category: .playback, mode: .spokenAudio)],
        purpose: "番組を再生"
    ),
    stop: { await feature.stopPlayerAndWait() },
    receive: feature.receiveAudioEvent
)
```

互換性は全ownerが明示したprofileの積集合だけで決まる。暗黙のcategory昇格やoption和集合は行わない。`.conflict`では製品UIが継続か`resolve(_:as:)`による明示切替を選び、coordinatorは旧producerのstop完了後だけ新requestを開始する。stop失敗後の`.partialStop`には実際に停止済み・残存するownerが入る。古いconflictは`.staleConflict`となり、新世代を停止しない。

`release`自身が登録済みstopをawaitする。stop closureはnative producerの停止完了までを担当し、同じleaseの`release`を呼ばない（`.stopReentry`）。lifetimeの`runtime.onShutdownAsync`から`release`をawaitする。`onSceneActivityChange`はFeature固有scene方針へ配送するが、画面消失や別Feature選択だけでは背景再生を解放しない。

Featureは再生・録音開始時に`updateIntent(.active, for:)`、ユーザー停止、remote pause、headphone抜去ではそれぞれ`.stoppedByUser` / `.stoppedForRouteChange`を設定する。interruption endの`.interruptionEnded(resumeCandidate:)`は候補通知にすぎず、Featureがproducer状態、lifetime、scene方針を確認する。fixtureは誤再開を避けるため候補表示だけを行う。

Now PlayingはFeatureごとに`MiniAppNowPlayingOwner`を持つ。session固有のinfo center/command centerを使い、ownerは登録tokenだけを削除する。同期remote handlerの`.success`はMainActorへのenqueue成功であり、操作完了ではない。停止時はcommand受付を閉じ、player停止、`invalidate()`、audio lease解放の順にする。

録音Featureは`MiniAppPermissionDeclaration`によるFeature同意と`AVAudioApplication.requestRecordPermission()`によるOS許可を別々に扱う。iOS 26のみのため旧permission API fallbackはない。親は`FeatureBuildRequirement`で`NSMicrophoneUsageDescription`を合成する。背景再生が必要なFeatureは同じ仕組みで`UIBackgroundModes = ["audio"]`を要求する（専用entitlementではない）。

撮影側の接続は次のhookを使う。camera予約後/native開始前に呼び、返ったclosureはその取得分だけを解放する。audio側stop callbackは撮影producer停止完了までで、closureを再帰的に呼ばない。

```swift
acquireAudio: (@MainActor @Sendable () async throws
    -> (@MainActor @Sendable () async -> Void))?
```

診断hostには`Tests/MediaAudio/`の全Swiftをapp targetへコピーし、`MediaAudioProbe.definitions`をregistryへ追加する。native test targetには`MediaAudioNativeTests.swift`を入れ、`@testable import JibunKit_App`を有効にする。外部素材は不要で、fixtureがローカルWAVを生成する。実機ではmicrophone許可後の実録音/録音再生、背景再生、通話等の中断、代表的な有線/Bluetooth切断、Lock Screen/Control Centerのremote command配送と停止後の非配送を確認する。simulatorでControl Centerが見えないことは配送成功としない。
