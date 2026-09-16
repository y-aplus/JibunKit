# AudioSession / Now Playing integration

`MiniAppAudioSessionCoordinator` は一つのhost processで一個を共有する。productionでは一個の`MiniAppNativeAudioSessionDriver`を作り、coordinatorへ注入して`connect(to:)`する。テストは独立driverを注入する。Featureはplayer/recorder、録音物、再生位置、再開判断を所有し、coordinatorは`AVAudioSession`構成だけを所有する。

```swift
let audio = MiniAppNativeAudio.coordinator // Capture bridgeも同じinstanceを注入する

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

Category/ModeはApple標準文字列、route policy/optionsは標準raw bitsを保持するSendable wrapperである。named constantsは便利APIにすぎず、`init(rawValue:)`で将来追加された標準値・bitも欠落なくnative adapterへ渡る。profile変更失敗は旧profileを再適用・activateしてrollbackし、rollback失敗は`.driverChangeFailed`と`.recoveryFailed`で明示する。

`release`自身が登録済みstopをawaitする。stop closureはnative producerの停止完了までを担当し、同じleaseの`release`を呼ばない（`.stopReentry`）。deactivate失敗時は停止済みleaseと`.deactivationFailed`を保持し、同じleaseの`release`再試行ではproducerを二重停止せずdeactivateを再試行する。`.coordinatorBusy`等の失敗はFeature終了成功として扱わない。lifetimeの`runtime.onShutdownAsync`から`release`をawaitする。

Featureは再生・録音開始時に`updateIntent(.active, for:)`、ユーザー停止、remote pause、headphone抜去ではそれぞれ`.stoppedByUser` / `.stoppedForRouteChange`を設定する。interruption endの候補後は、Featureがlifetime/scene/producer状態を確認して`reactivate(_:)`を明示的に呼ぶ。このAPIがprofile再適用とactivateを行うため、通知だけでplayerを再開しない。media-services resetも`.resetRequired`へ遷移し、同じAPIでnative構成を再構築する。ユーザー・route停止intentでは拒否される。

Now PlayingはFeatureごとに`MiniAppNowPlayingOwner`を持つ。session固有のinfo center/command centerを使い、ownerは登録tokenだけを削除する。同期remote handlerの`.success`はMainActorへのenqueue成功であり、操作完了ではない。実操作のBool結果は別の`onCompletion`へ届く。async `invalidate()`は受付を閉じてtokenを除去し、既に実行中の配送をjoinしてから返る。停止時はplayer停止、`invalidate()`完了、audio lease解放の順にする。

録音Featureは`MiniAppPermissionDeclaration`とhostの`MiniAppConsentStore`によるFeature ID別同意、および`AVAudioApplication.requestRecordPermission()`によるOS許可を別々に扱う。許可await後にはFeature操作世代を再検査し、停止済みなら開始しない。iOS 26のみのため旧permission API fallbackはない。親は`FeatureBuildRequirement`で`NSMicrophoneUsageDescription`を合成する。背景再生が必要なFeatureは同じ仕組みで`UIBackgroundModes = ["audio"]`を要求する（専用entitlementではない）。

撮影側の接続は次のhookを使う。camera予約後/native開始前に呼び、返ったclosureはその取得分だけを解放する。audio側stop callbackは撮影producer停止完了までで、closureを再帰的に呼ばない。

```swift
acquireAudio: (@MainActor @Sendable () async throws
    -> (@MainActor @Sendable () async -> Void))?
```

診断hostには`Tests/MediaAudio/`の支援Swiftをapp targetへコピーし、`MediaAudioProbe.definitions`をregistryへ追加する。native test targetには`MediaAudioNativeTests.swift`を入れ、`@testable import JibunKit_App`を有効にする。fixtureは外部素材不要のローカルWAVをloop再生する。自動testは注入permission/recording backendで遅着、停止待ち、失敗、中断再開、Bの世代保持を検査し、microphone未許可をskip成功にしない。実録音/録音再生、背景、通話中断、有線/Bluetooth切断、Lock Screen/Control Center配送は署名hostの実機手順として別に合格判定する。
