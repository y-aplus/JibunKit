# P2-F内の通常AR実装契約

2026-09-18。P2-12/D23。通常ARの採否は[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)の現本文166–172行相当と既存Capture実装を照合した。単一前景ARSessionの開始・停止・中断復帰を採用する。高度world map保存/共有・長期relocalization・background AR・複数ARSession/カメラの同時使用は今回の採用範囲に含めない。ARSession/ARConfiguration、run options、frame/anchor、描画方式を独自の狭い型へ閉じ込めない。

## 採用根拠と費用

既存MiniAppCaptureCoordinatorのcamera予約/切替、CaptureOwnerのpermission・scene activity・native event世代・停止join、FeatureLifetimeと管理/復元を再利用できる。新規の汎用resource manager、navigation、permission storeは作らない。追加の主な責任はARSessionとの接続と開始元sceneへの束縛であり、通常capture全体の再実装を要しない。採用判断は実装/検証の完了を意味しない。

P2-Sはb2f9a04で共有24/native13・IPAが成功。通常/shared439・Records11・通常IPAも同sourceで成功したがFiles復元UIが未完で、809822a/35296983783を限定再試験中。P2-Bの残る実OS動作、P2-Iの実CloudKit/APNs、P2-Sの実無線/iPadは未完として保持する。本契約でP2-Fや1.0全体の出荷gateを通過させない。

## 担当

- Sol lowの既存JibunKitプロジェクトスレッド: CaptureOwner/Coordinatorの明示scene scope、AR native adapter、Core試験、Tests/P2ARの通常Feature診断/native試験、AR接続ガイド。一括提出しCIは実行しない。
- 親: SceneActivityDispatcherの現在connection ID公開、SwiftUI environmentと実host注入、registry/Project/manifest/workflow、scope/台帳/証拠の管理。

親と子の契約は`EnvironmentValues.miniAppSceneActivityID: UUID?`。値は同じrootのMiniAppSceneActivity.sceneIDに一致し、切断でnil、再接続で新規IDになる。UISceneSessionの永続IDやwindow registry generationと混同しない。Captureの既存anyVisible契約は維持し、ARには明示scene(UUID)を使う。二windowに同Featureを表示すること自体を開始拒否の理由にしない。

## 所有と失敗

AR開始元のsceneがinactive/非選択/background/disconnectになると停止・camera解放。別windowの同Feature表示によって継続させない。OS interruption中の一時停止とscene終了を分け、再開方針はFeatureが提供する。backgroundから戻っただけでは暗黙に開始しない。拒否されたB要求はAを変えず、stopCurrentではAのpause/解放後にBへ渡す。

delegate/frame APIをFeatureから奪わない。native delegate queue、世代検査、停止後の遅着、delegate forwardingの責任を明示する。Swift6 actor isolationは提出前にまとめて確認する。明示initializerを用い、非隔離async XCTest helperへMainActor closureを送らない。

## 検証境界

Coreでは指定scene、permission待ち中の離脱、停止/再開/中断失敗、A/B競合とB保持、古い世代拒否を検証する。Simulatorはnative compile・通常Definition接続・非対応の明示拒否・注入callbackまで。実tracking/frame、実camera切替とOS interruptionは対応端末で一括確認し、fakeやSimulatorの成功で代用しない。

CIはワーカー提出と親レビュー後、P2-Fの残る採否/依存範囲を確認して投入前reportへ固定する。ARの小変更ごとには回さない。既存成功sourceの再利用理由、必要な回帰範囲、準備/upload込み25分以内の見込みを記載する。現在ARのCI投入は0回。実機確認依頼は候補の自動検証と手順準備後に行う。
