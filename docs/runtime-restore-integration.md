# Runtimeと復元の接続ガイド

## 利用できる能力

共有バックアップ画面は、選択されたFeatureの停止→適用→再開を呼ぶ。同一Featureの復元・snapshot書出しはプロセス内で重複を拒否し、他Featureの処理を一括停止しない。Runtimeは新規Task受付を閉じ、既存Taskの終了と同期/非同期の資源解放を待つ。

これはDBエンジンの選択を制限しない。個別DBの接続解放、購読解除、通常書込みの受付停止はFeatureが実装する。Runtimeへ未登録の仕事は自動検出できない。

## 所有者から再開まで

1. Featureの所有者を画面の一時的な再生成より長く保持し、その所有者が現在のRuntimeと保存層を保持する。同じFeatureの複数画面はこの所有者を共有する。
2. 資源を取得した時点で`onShutdown`または`onShutdownAsync`へ解放を登録する。その後に資源を使うTaskを`start`で登録する。Taskの中断処理は取消に協調して終了する。
3. UI以外の書込み入口も同じ所有者を通す。Runtimeを使うTask受付はshutdown時に閉じるが、同期メソッドや外部callbackの受付は所有者側でも閉じる。
4. `MiniAppDefinition.restoreLifecycle.stop`から受付を閉じ、`await runtime.shutdown()`を待つ。所有Taskの終了後、解放hookが逆順で完了する。解放hookから自分のshutdownを待つと自己待ちになるため避ける。
5. backup providerのprepareは検証と準備だけを行う。返したapplyが、停止完了後の保存先を置き換える。Files/JSONを扱う共有画面はこの順序で呼ぶ。
6. resumeで保存層を再接続し、新しいRuntimeへ所有者の参照を差し替えて受付を再開する。画面は古いRuntimeを個別に保持せず、所有者経由で処理を始める。
7. 直接planを使う経路では`apply(lifecycles:)`にhookを渡す。共有画面ではDefinitionから収集済みなので別のhost内Feature分岐は不要。

## 実際の接続例

[LifecycleProbeIntegration.swift](../Tests/TemplateIntegration/LifecycleProbeIntegration.swift)はCI専用の小さな二Feature接続例。`LifecycleProbeState`がRuntimeを保持し、`start`、`shutdown`、`resumeAfterRestore`で受付と差替えを行う。Definitionにはbackup providerとrestoreLifecycleの両方を登録し、実際のBackupScreenへ接続している。`applyRestored`はRuntimeの停止完了を確認してから値を変更する。

この例はDB製品ではない。実DBでは、接続解放と再接続、トランザクション、外部プロセスのロックを保存層に合わせて実装する。非同期解放と復元planの結合は[MiniAppRuntimeTests](../Tests/JibunKitCoreTests/MiniAppRuntimeTests.swift)にある。

## 失敗と競合

| 状況 | 現在の共有経路の動作 | Feature側の責任 |
| --- | --- | --- |
| 別の復元・snapshot作成と対象が重複 | 停止・適用前にConflictを返す | 同じ保存先には同じcoordinatorを使う |
| stopがthrow | 任意のrecoverAfterFailedStopを待ち、apply/resumeを呼ばない | callbackを登録するか、stop自身で利用可能な状態へ戻す |
| stop後の回復もthrow | 両方の理由を保持し、stopAndRecoveryとして未復元・利用状態への回復失敗を報告 | 部分停止した資源を診断し、利用受付を安全な状態に保つ |
| applyがthrow | resumeを試み、後続Featureは変更しない | 部分変更を想定した保存層の回復 |
| resumeがthrow | データ適用済みと再開失敗を区別して報告 | 再接続失敗後の利用制限・回復 |
| 取消済みで開始前 | 何も変更せず終了 | 取消を無視する独自入口を作らない |
| 複数Feature途中で取消 | 着手済みの再開を終え、次の着手前に中止 | 完了済みを全体rollbackと誤認しない |

## 検証済みの範囲と残件

`recoverAfterFailedStop`は停止途中で失敗した資源のための任意callbackで、正常に停止した後の`resume`とは別である。登録しなければ従来通りstop自身が回復する。callbackが成功しても復元は失敗として終了し、後続Featureは開始しない。実行中は同じcoordinatorの復元・snapshot予約を保持し、取消されても回復の完了を待つ。callback内の取消に弱いAPIはFeatureが扱う必要がある。通常書込みの受付までこの予約で自動制御するものではない。

DB接続の状態確認、必要な再接続、新しいRuntime作成、UI以外の受付再開をこの順序で行う。閉じられた接続も生きた接続もある途中状態から、検査なしに一律再生成してはならない。[停止失敗回復の検証記録](verification/2026-09-11-restore-stop-recovery.md)を参照。

- unit: 受付閉鎖、Task完了待ち、同期/非同期解放順序、同時shutdown合流、重複予約拒否、取消、snapshotとの競合、他owner継続。
- CIの実画面: 選択復元の成功と4つの失敗経路、AのRuntime再開とBのTask/データ維持。
- ユーザー実機: カウンターJSONの書出し・読込み・選択・上書き復元。
- 残件: 特定DB接続の実装と比較検証、通常書込みや購読の一般接続、Widget等の別プロセスとの排他、移行/リセットの接続。D02/D07全体の完成は未達。

個々のCIと未解決のSimulator Files操作は[検証記録](verification/2026-09-10-runtime-lifetime.md)、現在の全体判定は[統合差分台帳](coexistence-ledger.md)を参照。
