# Feature所有の撮影・文書／コードscan

対象はiOS 26以上。JibunKitはcameraのowner別受付と寿命を管理し、撮影構成、native object、成果物、保存形式はFeatureが所有する。cameraとmicrophoneは別資源で、camera-only操作はAudio調停を要求しない。

## 接続

プロセスでは`MiniAppCaptureCoordinator.shared`をFeature factoryへ注入する。テストでは独立instanceを注入できる。`MiniAppDefinition`へpropertyは追加せず、Featureの`MiniAppFeatureLifetime.configure`で`MiniAppCaptureOwner.connect(to:)`し、`onSceneActivityChange`を`owner.receive(_:)`へ渡す。

```swift
@MainActor
func makeFeature(coordinator: MiniAppCaptureCoordinator,
                 consentStore: MiniAppConsentStore) -> MiniAppDefinition {
    let id = MiniAppID("receipt")
    let capture = MiniAppCaptureOwner(
        id: id, coordinator: coordinator,
        permissions: MiniAppAVCapturePermissionClient(),
        consent: { resource in
            consentStore.consent(for: id, permissionID: resource.rawValue) == .allowed
        }
    )
    let lifetime = MiniAppFeatureLifetime(id: id) { runtime in
        try capture.connect(to: runtime)
    }
    return MiniAppDefinition(
        id: id, title: "Receipt", systemImage: "doc.viewfinder",
        lifetime: lifetime,
        permissions: [.init(id: "camera", title: "カメラ",
            purpose: "領収書を撮影します", deniedBehavior: "scanを開始しません")],
        onSceneActivityChange: { capture.receive($0) }
    ) { _ in ReceiptView(capture: capture) }
}
```

hostは既存`FeatureBuildRequirement`で`NSCameraUsageDescription`を合成する。音声付き動画だけは`NSMicrophoneUsageDescription`も宣言する。`MiniAppPermissionDeclaration`による既存管理UIの判断を`MiniAppConsentStore.consent(for:permissionID:)`からownerの`consent` closureへ渡し、その後adapterのOS許可を要求する。store未注入、`.notDetermined`、`.denied`はいずれもOS dialogの前に拒否する。独自の永続Boolは追加せず、Feature同意とapp全体のOS許可を同じ許可として扱わない。

## operationと停止

`MiniAppCaptureOperation`の`startNative`はnative producerの開始完了後、停止完了をawaitできるclosureを返す。開始途中でthrowする実装は、まだstop closureを返せないため、自身が取得済みnative資源を先に解放する。`nativeEvents`と`restartNative`を渡したAVFoundation operationは、世代付きの中断開始／終了／runtime error値をownerへ届ける。初期`startRunning()`失敗は`.initialization`、開始後の通知は`.runtime`で区別する。runtime errorのうちmedia services resetだけを再開候補とし、可視・同一世代・ユーザー停止前の条件を再検査する。`AVCaptureSession` graphは`MiniAppAVCaptureSessionProducer` actorから外へ出ない。

VisionKitは`MiniAppVisionCaptureAdapter`がMainActor上でcontrollerとoperation generationを所有し、既存`MiniAppPresentationOwner`へ提示を登録する。旧controller、多重tap、終端後のdelegateは無視する。`startScanning()`失敗は提示dismiss完了までjoinしてからthrowし、`becameUnavailableWithError`はFeatureへ失敗理由を返す。interactive dismissとnavigation dismissも同じownerのcamera予約を解放する。

inactive、background、非選択は、そのownerにactiveかつselectedな別sceneがなければ停止する。Feature停止、許可待ち取消、開始失敗でも、native capture停止（未完了photoとmovie `didFinishRecording`を含む）→presentation dismiss完了→関連lease解放の境界をawaitする。ユーザー停止は復帰通知で取り消さない。古いruntime／operation／native session generationの許可結果・通知・delegate結果は採用しない。

同じcameraが使用中なら既定の`.reject`は`.cameraInUse(by:)`を返す。ユーザーが明示した切替だけ`.stopCurrent`を渡し、旧producerの停止・解放完了後に新ownerを開始する。Feature内部で一つのproducerが組むMultiCam graphは一予約として扱い、Coreが固定単眼構成へ変換しない。

## 音声付き動画

microphoneを要求するoperationには、契約固定のhookを必ず注入する。

```swift
MiniAppCaptureOperation(
    resources: [.camera, .microphone],
    acquireAudio: makeAcquireAudio(owner, stopNativeOnly),
    nativeEvents: { await producer.events() },
    restartNative: { try await producer.restartAfterInterruption() },
    startNative: {
        try await producer.start()
        return { _ in await producer.stop() }
    }
)

// fixture側の親bridge
MediaCaptureProbe.makeAcquireAudio = { owner, stopNativeOnly in
    {
        let lease = try await audio.acquire(owner: owner, stopProducer: stopNativeOnly)
        return { await audio.release(lease) }
    }
}
```

operationの型は契約どおり`(@MainActor @Sendable () async throws -> (@MainActor @Sendable () async -> Void))?`。fixtureのfactoryはowner IDとnative-only stop callbackからこの型を返す。camera確保後、native開始前に呼ばれる。microphone要求でnilなら`.missingAudioHook`、取得失敗ならcamera予約を返す。camera-onlyへ暗黙downgradeしない。native adapterは共有application AudioSessionを使い、audio hook統合時に自動構成を止める。private AudioSessionで調停を迂回しない。Audio側stop callbackはproducer停止だけを行い、`owner.stop()`や同じlease解放closureを再帰awaitしない。

## fixtureと確認

`Tests/MediaCapture/MediaCaptureProbe.swift`は親が診断app targetへコピーする公開入口`MediaCaptureProbe.definitions`を持つ。親は同じMainActor上の`MediaCaptureProbe.makeAcquireAudio`へP2-1 bridge factoryを設定する。撮影Featureは実`AVCapturePhotoOutput`と音声付き`AVCaptureMovieFileOutput`経路、scan Featureは実`VNDocumentCameraViewController`と`DataScannerViewController`経路を提供する。写真Data、保持する一つのmovie URL、文書page Data、code文字列は各Feature stateが所有し、画像preview・動画再生・文字列表示で目視できる。新しいmovie開始時に旧一時fileを削除し、失敗movieも削除する。画面には中断／失敗／停止、成果件数、保持値、runtime世代を表示し、音声bridge未注入時は「Audio接続未統合」と明示する。

`Tests/MediaCapture/MediaCaptureNativeTests.swift`は注入可能な実Feature factoryとVision adapterを`@testable import JibunKit_App`で検査し、停止join、A停止後のBの非初期値／同一runtime generation、同意拒否、scanner開始失敗、旧delegate拒否、外部dismissと別owner提示保持を確認する。Foundation状態試験は`Tests/JibunKitCoreTests/Capture/`にあり、競合、明示切替、stop中、許可callback遅着、scene集約、Audio解放順、世代付き中断／runtime失敗をfakeで検査する。

実機ではcamera許可の許可／拒否、写真成功、文書成功／取消、QR成功、background／foreground、Feature切替、音声統合後の短時間動画と他owner音声保持を確認する。SimulatorやmacOS試験を実camera、VisionKit対応（DataScannerは対応hardwareが必要）、OS許可UI、音声経路の証拠にしない。

Apple一次資料: [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)、[startRunning](https://developer.apple.com/documentation/avfoundation/avcapturesession/startrunning())、[runtimeErrorNotification](https://developer.apple.com/documentation/avfoundation/avcapturesession/runtimeerrornotification)、[AVCaptureFileOutputRecordingDelegate](https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate)。
