# Feature所有の撮影・文書／コードscan

対象はiOS 26以上。JibunKitはcameraのowner別受付と寿命を管理し、撮影構成、native object、成果物、保存形式はFeatureが所有する。cameraとmicrophoneは別資源で、camera-only操作はAudio調停を要求しない。

## 接続

プロセスでは`MiniAppCaptureCoordinator.shared`をFeature factoryへ注入する。テストでは独立instanceを注入できる。`MiniAppDefinition`へpropertyは追加せず、Featureの`MiniAppFeatureLifetime.configure`で`MiniAppCaptureOwner.connect(to:)`し、`onSceneActivityChange`を`owner.receive(_:)`へ渡す。

```swift
@MainActor
func makeFeature(coordinator: MiniAppCaptureCoordinator) -> MiniAppDefinition {
    let id = MiniAppID("receipt")
    let capture = MiniAppCaptureOwner(
        id: id, coordinator: coordinator,
        permissions: MiniAppAVCapturePermissionClient()
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

hostは既存`FeatureBuildRequirement`で`NSCameraUsageDescription`を合成する。音声付き動画だけは`NSMicrophoneUsageDescription`も宣言する。`MiniAppPermissionDeclaration`によるFeature同意を先に確認し、その後adapterのOS許可を要求する。両者を同じ許可として扱わない。

## operationと停止

`MiniAppCaptureOperation`の`startNative`はnative producerの開始完了後、停止完了をawaitできるclosureを返す。`AVCaptureSession` graphは`MiniAppAVCaptureSessionProducer` actorから外へ出ない。VisionKitは`MiniAppVisionCaptureAdapter`がMainActor上で所有し、既存`MiniAppPresentationOwner`へ提示を登録する。

inactive、background、非選択は、そのownerにactiveかつselectedな別sceneがなければ停止する。Feature停止、許可待ち取消、開始失敗でも、native capture停止→presentation dismiss完了→関連lease解放の境界をawaitする。ユーザー停止は復帰通知で取り消さない。古いruntime／operation generationの許可結果とdelegate結果は採用しない。

同じcameraが使用中なら既定の`.reject`は`.cameraInUse(by:)`を返す。ユーザーが明示した切替だけ`.stopCurrent`を渡し、旧producerの停止・解放完了後に新ownerを開始する。Feature内部で一つのproducerが組むMultiCam graphは一予約として扱い、Coreが固定単眼構成へ変換しない。

## 音声付き動画

microphoneを要求するoperationには、契約固定のhookを必ず注入する。

```swift
MiniAppCaptureOperation(
    resources: [.camera, .microphone],
    acquireAudio: { // 親がP2-1 coordinatorへ接続
        let lease = try await audio.acquire(/* owner/profile/stop producer */)
        return { await audio.release(lease) }
    },
    startNative: { /* producer開始、await可能なstopを返す */ }
)
```

型は`(@MainActor @Sendable () async throws -> (@MainActor @Sendable () async -> Void))?`。camera確保後、native開始前に呼ばれる。microphone要求でnilなら`.missingAudioHook`、取得失敗ならcamera予約を返す。camera-onlyへ暗黙downgradeしない。native adapterは共有application AudioSessionを使い、audio hook統合時に自動構成を止める。private AudioSessionで調停を迂回しない。Audio側stop callbackはproducer停止だけを行い、そのcallbackから同じlease解放closureを再帰awaitしない。

## fixtureと確認

`Tests/MediaCapture/MediaCaptureProbe.swift`は親が診断app targetへコピーする公開入口`MediaCaptureProbe.definitions`を持つ。親は同じMainActor上の`MediaCaptureProbe.acquireAudio`へP2-1 bridgeを設定できる。撮影Featureは実`AVCapturePhotoOutput`と音声付き`AVCaptureMovieFileOutput`経路、scan Featureは実`VNDocumentCameraViewController`と`DataScannerViewController`経路を提供する。結果Data、movie URL、page数、code文字列は各Feature stateが所有する。画面には成功／失敗／停止、成果件数、保持値、runtime世代を表示する。音声付き動画はclosure未注入時に「Audio接続未統合」と明示する。

`Tests/MediaCapture/MediaCaptureNativeTests.swift`はapp targetへコピーされたfixtureを`@testable import JibunKit_App`で検査し、A停止後もBの非初期値と同一runtime generationを保持する。Foundation状態試験は`Tests/JibunKitCoreTests/Capture/`にあり、競合、明示切替、stop中、許可callback遅着、scene集約、Audio解放順をfakeで検査する。

実機ではcamera許可の許可／拒否、写真成功、文書成功／取消、QR成功、background／foreground、Feature切替、音声統合後の短時間動画と他owner音声保持を確認する。SimulatorやmacOS試験を実camera、VisionKit対応（DataScannerは対応hardwareが必要）、OS許可UI、音声経路の証拠にしない。
