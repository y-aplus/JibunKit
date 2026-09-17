# P2-S: BLEと通常複数window

2026-09-18開始。P2-9/D24とP2-11/D01,D04。P2-Iの共有/通常CI35249566535とnative12件CI35253192466を継承する。実APNs/CloudKit通信、P2-Bの背景/cold/電波確認は未完のまま別管理し、この作業で完了扱いしない。ユーザー睡眠中は実機操作を要求しない。

## 所有と契約

JibunKit projectのSol low別スレッド2本。ワーカーはCIを実行せず、担当パスの実装・試験・ガイドをまとめて提出する。親がレビューして通常/sharedと両領域のnative検証を一つの境界として固定する。初回予算3run、遅くとも3失敗ごとに原因切り分け。準備/upload込み25分見込みを事前に記録し、完了通知のみで再開する。元のC:/Dev/JibunKitのdirty files/ignored Zaikoは変更しない。mainへ未検証統合しない。

既存MiniAppDefinition/ID/Context、FeatureLifetime/Runtime、管理/外部受付・選択復元・scene routerと宣言合成を再利用する。native APIを不要に狭いfacadeへ閉じ込めず、所有/停止/調停の不足を補う。通常A/B同時動作、片側停止・削除・失敗・復帰で他方の非初期状態を保持する。fake成功、Simulator OS操作、実機/電波を区別する。

## BLE担当

所有: Sources/JibunKitCore/Bluetooth/、Tests/JibunKitCoreTests/Bluetooth/、Tests/P2Bluetooth/、docs/guides/bluetooth-ownership.md、docs/delivery/P2-bluetooth-submission.md。

CoreBluetooth centralの通常scan/connect/disconnect、電源/許可、service/characteristic discovery、read/write/subscribeを扱う。owner別manager/restore identifierとperipheral/delegate lifetimeを設計し、停止・遅着・重複・再接続を区別する。同じ周辺機器に複数Featureが関わる場合も所有契約を明示し、他ownerの接続を誤って取消さない。background-centralのnative state restorationは同期host launch hookへ接続し、無効ownerを復活させない。標準CB型の利用余地を残す。汎用BLEプロトコル/特殊機器網羅/peripheral role一般化はしない。

Tests/P2Bluetooth/P2BluetoothProbe.swiftで通常二Feature定義を公開、P2BluetoothNativeTests.swiftで同じ定義/管理を通す。Simulatorに電波能力がないことを明示し、adapter compileとfake callbackを実無線受信と呼ばない。使用説明/背景mode/復元接続の必要宣言は提出に示す。host/manifest/workflowは親が所有。

## scene担当

所有: Sources/JibunKitCore/WindowScenes/、Tests/JibunKitCoreTests/WindowScenes/、Tests/P2Scenes/、docs/guides/window-scene-ownership.md、docs/delivery/P2-scenes-submission.md。既存scene routerを変える必要があれば親へ変更対象と理由を一度まとめて通知する。

通常iPad二windowの生成・独立navigation/Feature状態・指定scene配送・破棄・復帰を扱う。OS session identityと一時connection generationを分け、古いscene参照へ遅着させない。windowを閉じても別windowの同一Featureや別Featureを勝手に止めない。Feature global lifetimeとscene単位資源を区別する。既存SceneStorage/navigationを再利用し、任意Viewの自動serializationや全FeatureのCodable強制はしない。

Tests/P2Scenes/P2ScenesProbe.swiftとP2ScenesNativeTests.swiftに二scene/ownerの通常接続試験とiPad OS操作用診断を用意する。実二windowのOS検証はiPad Simulator/実機を区別し、二つのSwiftオブジェクトだけでOS成功としない。必要なhost Scene/manifest接続を具体的に提出する。Sources/JibunKit、Project.swift、workflowは親が所有。

## 提出とレビュー

Swift6 actor isolation、escaping closure capture、XCTest helper隔離を提出前に一括確認する。前境界のコンパイル修正を繰り返さない。SwiftがないWindowsでは実行済みと書かず、API署名はApple一次資料で照合する。管理停止→native取消/join→削除/復元の順序を試験に含める。提出は実装commit、未実行一覧、接続手順と条件、残件を一度通知する。親はsource確定後に同一SHAの検証を組む。
