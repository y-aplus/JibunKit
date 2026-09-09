# Feature runtimeの終了境界

## 対象

実装source: `0c87765`。CI: [34371355575](https://github.com/y-aplus/JibunKit/actions/runs/34371355575)（Runtime unit・idle終了接続成功、run全体はWeb Cookie再起動後読出し失敗）。

独立アプリの終了では、そのプロセスのTaskや資源利用は他アプリの処理と別に終わる。単一hostへ統合したFeatureでは画面を閉じるだけでそれを得られない。今回の実装は協調的なTaskと後始末の順序を提供する。独立processの強制終了能力は提供しない。

## 契約と検証

| 契約 | 検証 |
| --- | --- |
| 最初のshutdownで新規受付を閉じる | unitで終了後start/onShutdownの拒否。終了待ち途中の拒否・同時shutdownの完了待ちを追加、次のunit CI待ち |
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

[34373928804](https://github.com/y-aplus/JibunKit/actions/runs/34373928804)でRuntimeを含むCI全体成功。次のunitではTaskの取消後処理をcontinuationで止め、資源が先に解放されないことを検証する。owner解放時にもTask終了→資源解放の順序を確認する。固定sleepによる順序推定は行わない。


## 選択復元への接続

34378410196でstop/apply/resumeと各失敗経路のunit成功。次のiOS検証は二つのCI専用Featureを起動し、Aだけを製品BackupScreenから上書き確認付きで復元する。providerはRuntime閉鎖・Task終了が確認できないとapplyを拒否する。resumeは新しいRuntimeへ差し替える。Aの新Taskが正常完了でき、Bの既存Taskと元データが維持されることを確認する。

入力は有効なMiniAppBackupを画面の既存初期化引数で渡す。Files pickerの読込み検証とは分ける。Fixtureは通常IPAには含まれない。実FeatureのDB再接続や並行復元の排他は、このテストだけでは完了しない。

## 選択復元のiOS検証結果

[34379082689](https://github.com/y-aplus/JibunKit/actions/runs/34379082689)（source `99aca5faff96121ed61bc5a006940151bc53488d`）で `testSelectedRestoreStopsAndRestartsOnlyItsRuntime` が49.466秒で成功した。実際のBackupScreenからAを選択して復元し、停止完了を必須にするproviderの適用、新しいRuntimeでのTask実行、Bの既存Taskとデータの維持を確認した。同じrunでidle要求の終了調停44.310秒、片方だけのTask取消46.383秒も成功した。

generated host UIは12件中11件成功、Webデータ再起動保持の1件が失敗したためrun全体は失敗。共有ロジックテスト、独立Featureのビルド、IPA生成は成功したが、後続の通常host回帰はスキップされている。全体成功とは扱わない。

選択復元の成功経路は確認済み。停止・適用・再開の失敗順序はunitで確認しているが、製品画面の失敗表示、実FeatureのDB接続解放と再接続、複数sceneから同じFeatureへ同時復元する場合の排他は未完である。現状の画面は失敗したFeatureと先行完了したFeatureを示すものの、データ適用失敗とRuntime再開失敗を区別して表示しない。この差分も以後の復元調停に含める。
