# P2-I: 外部データidentityとPush配送

2026-09-18開始。P2-8/D30とP2-10/D14,D26。P2-B背景/位置の実機残件とは独立に進める。ユーザーは約8時間不在、iPad確認は起床後以降。iOS継続処理code1の追加追究は停止。背景URLSessionの背景callback/保存/完了はf6f6c04で実機確認済み、終了後cold起動とは区別する。

## 共通契約

通常のFeature定義・MiniAppID/Context・FeatureLifetime/Runtime・管理/選択復元・既存宣言合成を再利用する。二ownerで同じローカル識別子、A停止/削除/復元・B非初期値保持、世代の遅着、account/token変更を検証する。独立アプリなら得られる境界との差分を補い、汎用同期backendや全認証方式の一般化は作らない。OS/署名/外部server条件と未実装を区別する。

ワーカーは実装・試験ソース・手順をまとめて提出する。CIは実行しない。親が二提出の契約を照合して一つのCI境界を固定する。初回予算3run、3失敗までに原因を切り分け。途中commitはCI起動条件ではない。親はhost/manifest/workflow、台帳・出荷文書、統合fixtureの接続を所有する。元のC:/Dev/JibunKitとignored Zaikoは変更しない。調査は必要なApple一次資料を参照するが別の研究タスクへ広げない。

## 外部identity担当

所有path: Sources/JibunKitCore/ExternalIdentity/、Tests/JibunKitCoreTests/ExternalIdentity/（実際の既存testsディレクトリ構造に合わせる）、Tests/P2Identity/、docs/guides/external-data-identity.md、docs/delivery/P2-identity-submission.md。

container/account/dataの所有境界を明示するAPIと通常Feature接続。CloudKitの標準型・record zone/record ID/subscription等の名前空間、account変更時の旧世代/取消/結果隔離、Aの削除/復元でBを保つ範囲を実装する。任意containerの自動移行や業務sync engineは作らない。native CloudKit接続を含み、署名/entitlementなしの診断hostを起動だけで落とさない。利用可能な構成の事前条件を明示し、注入backendの成功を実CloudKit通信成功と呼ばない。Tests/P2Identity/P2IdentityProbe.swiftに二つのMiniAppDefinitionを公開し、P2IdentityNativeTests.swiftで所有/遅着/account変更/失敗/復旧を検証する。共通hostへの追加は親が行う。

## Push担当

所有path: Sources/JibunKitCore/RemotePush/、Tests/JibunKitCoreTests/RemotePush/（既存test構造に合わせる）、Tests/P2Push/、docs/guides/remote-push.md、docs/delivery/P2-push-submission.md。

app単位APNs tokenとFeature/server identity、登録失敗・token更新・owner解除・世代遅着、正しい通知/背景配送とcompletion集約を実装する。既存通知router/外部routeと統合し、payloadのownerを全Featureへbroadcastしない。server別業務処理はFeature所有。必要なnotification service/content extensionは通常範囲の採否と接続案を示す。汎用backendは作らない。Tests/P2Push/P2PushProbe.swiftの二MiniAppDefinitionとP2PushNativeTests.swiftを用意する。UIApplicationDelegateへの具体的な呼出し/署名条件は提出文書へ示し、host/Project.swiftを直接編集しない。実APNs登録成功や配信は署名/server条件付きでありfake callbackと区別する。

## 親の並行作業と検証境界

親は既存通知delegate/宣言合成とCloudKit/APNs署名条件を確認し、二fixtureの使い捨てnative host、全method照合、通常host回帰をまとめる。提出前の重複実装はしない。契約の根幹が変わる問題はまとめて報告し、細かなAPIごとの承認待ちにはしない。CIの正確な入力/filter/時間上限はソース統合後に追記する。
