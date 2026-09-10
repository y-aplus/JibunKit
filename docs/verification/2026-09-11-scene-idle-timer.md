# D05 scene選択とidle timer要求の接続

状態: 実装済み、CI確認待ち。main未統合。

## 補完する差分

Feature Aの表示中に取得した画面点灯要求が、Bへ切り替えてもhost全体へ残る差分を補う。任意の`MiniAppSceneIdleTimer`で要求の意図と実leaseを分離し、ownerが選択されたactive sceneがある間だけ有効にする。従来の明示lease契約は維持する。

## 検証計画

- 四つのunit: 選択離脱/復帰・背景化、他ownerの明示lease維持、複数sceneとforeignイベント、Runtime終了/閉鎖後の再取得拒否・同ownerの別scope維持、native apply再入中のclose後始末。
- 署名付き生成hostの`testSceneIdleRequestSuspendsResumesAndPreservesOtherOwner`: A要求、OS背景化時の解除と復帰、B選択時の解除、Bの明示要求を維持したA復帰とRuntime終了、B解除後の通常設定、A閉鎖後の再取得拒否。`UIApplication.shared.isIdleTimerDisabled`とowner集合を読み戻す。
- 共有/独立Feature・通常IPA・通常host通知遷移・Records回帰。Windowsではdiffと対象selectorの存在を確認する。

## 境界

Simulatorで共有設定を読み戻す試験であり、実機が放置後に暗転/ロックすることの検証ではない。二つのOS windowを操作する試験でもない。任意のViewやsheetの被覆、非協調的な直接setter、外観・輝度等の共有設定は残る。D05全体は未対応のまま。
