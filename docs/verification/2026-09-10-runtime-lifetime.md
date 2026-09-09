# Feature runtimeの終了境界

## 対象

実装source: `0c87765`。CI: [34371355575](https://github.com/y-aplus/JibunKit/actions/runs/34371355575)（結果待ち）。

独立アプリの終了では、そのプロセスのTaskや資源利用は他アプリの処理と別に終わる。単一hostへ統合したFeatureでは画面を閉じるだけでそれを得られない。今回の実装は協調的なTaskと後始末の順序を提供する。独立processの強制終了能力は提供しない。

## 契約と検証

| 契約 | 検証 |
| --- | --- |
| 最初のshutdownで新規受付を閉じる | unitで終了後start/onShutdownの拒否。終了待ち途中の拒否は追加検証が残る |
| 所有Taskの取消後、終了してから資源を解放する | 実行中AsyncStream Taskの終了記録とcleanup順序をunitで比較 |
| cleanupは逆順、shutdownの重複呼出しで重複しない | 同時shutdown二呼出しの記録をunitで比較 |
| 他runtimeの資源利用は維持する | 二ownerのidle leaseを使い、片方終了後のactiveOwnersを確認 |
| 実際のiOS設定へ接続する | CI隔離hostで二Featureのidle要求を取得後、順番にruntime.shutdown。最後だけOS設定が解除されることを確認 |

## 前提となる確認済み証拠

[34367286197](https://github.com/y-aplus/JibunKit/actions/runs/34367286197)では、runtime接続前のidle leaseのiOS設定読戻しが49.277秒で成功。同じrunで通知action回帰67.236秒、Webデータ通常background経由の再起動保持74.875秒も成功した。

## 未完の範囲

- hostのFeature無効化・scene終了・選択復元前停止への一般接続。
- Task以外の購読や外部要求をどの契約で停止・完了待ちするか。
- 非協調Taskやruntimeを強く保持する循環参照。明示終了や所有側の設計が必要。
- Task自身からshutdownして自己完了を待つ誤用の検出。
- idle timerの端末点灯動作。今回は設定値の調停を検証する。

D01/D02/D05/D07全体を補完済みとは判定しない。現在状態の正本は[統合差分台帳](../coexistence-ledger.md)。
