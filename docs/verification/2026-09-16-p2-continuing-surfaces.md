# P2-L / 0.8.2 開発・検証記録

更新日: 2026-09-16。**実装中。Swift/native CI・実機未確認、0.8.2未公開。**

対象はP2-5 / D28のLive Activities・AlarmKit。公開済み0.8.1は[出荷記録](2026-09-16-0.8.1-release.md)のまま。通常checkoutのローカル変更・Zaikoは変更しない。

## 契約と分担

[固定した契約](../delivery/P2-continuing-surfaces-contract.md)を正本とする。設計提出の提案は、この文書と契約の採否決定が優先する。設計baselineはbcfde0d、実装baselineはe46209cc5a4563b09026421dce0d1b035ddef19b。

CLI sol/lowの二レーンが、同じbaselineから型付きnative adapter・A/B fixture・Intent/表示・失敗試験・開発者ガイドを実装中。親は共通保存/直列化・通常管理/復元・host接続と統合検証を担当する。独立workerの初回設計各1提出、実装は未提出。workerごとのCIは起動していない。

## 親の実装

- `MiniAppContinuingIdentity`はowner/local ID/業務世代/登録UUIDを区別する。OS対応表を業務backupと分離し、管理で業務受付を閉じた後も解除対象を読める。
- `MiniAppContinuingJournal`はowner/namespaceごとの短い同期ファイル調停とatomic保存。async OS呼出しを調停中に行わない。pendingを残し、破損を空として処理しない。実際のnative操作との途中終了回復は各adapterの責任として試験する。
- `MiniAppContinuingOperationGate`はawaitをまたぐnative操作を直列化し、closeは進行中をdrainする。管理用照合/後始末はclosedでも利用可能。process間business stateの調停は既存externalAccess/SharedStateであり、このgateで代替しない。
- Definitionのoptional `continuingSurfaces`、`effectiveExternalAccess`、`effectiveRestoreLifecycle`を通常hostへ接続。無効化/削除では解除成功後に完了へ進む。復元はgateを閉じ、既存の復元停止とOS解除を終えてから適用する。再有効化/復元resumeから活動を暗黙再開始しない。
- 起動/foregroundの再照合は画面taskと分離。enabled ownerごとに実行し、同ownerの重複taskを避ける。照合失敗は管理画面に表示し、対象ownerだけ再確認できる。無効化未完了の解除は既存管理の再試行へ残す。

## 現時点の検証

| 検証 | 結果と限界 |
|---|---|
| Python Tools試験 | 77件成功（Windows、11.477秒）。その後の管理画面表示追加はSwift実行検証待ち |
| 既存操作Widget診断host生成 | 3件成功。hostがeffectiveExternalAccessを利用する変更へ既存assertionを更新 |
| `check-delivery.py` plan検査 | 25単位/12境界で成功。P2-Lの証拠合格や出荷合格ではない |
| 共通Swift試験 | `MiniAppContinuingSurfaceTests` 10件を追加。WindowsにSwift/Xcodeがなく未実行 |
| Native adapter / A/B fixture | 各workerが実装中。提出レビュー前 |
| CI / 実機 | 本境界では未投入・未実施 |

共通Swift試験はjournal再構築・片側失敗/Bの保存bytes保持、破損/重複登録拒否、await中の直列化、close/drainと取消、OS解除失敗時のremoving維持と再試行、復元前解除/世代変更/自動再開始なし、停止失敗時の元データ保持、複数surfaceの一部失敗、close失敗時にも永続受付閉鎖、復元中の管理無効化をresumeが覆さないこと、復旧失敗時の閉鎖維持を扱う。fake成功はAlarmKit/ActivityKitの実動作の証拠にしない。

## 次の統合判定

両実装を一括レビューしてからCI用sourceを固定する。特に、同ownerが複数のattributes型を使う場合のnamespace分離、OS登録成功/保存失敗からの回復、世代/登録UUIDの両照合、解除のbounded待機、Alarm置換の部分成功、OS許可がapp単位であることを確認する。

初回予算は2run。独立/統合native build・App Intents metadata・共通試験・通常hostの管理/復元を同一sourceの並列jobへまとめ、必要な通常IPA/回帰と分担する。具体的なworkflow input/filter、変更で無効になる既存証拠、準備/uploadを含む25分見込みは提出統合後・投入前に記録する。未確定の入力を「準備済み」としてCIを起動しない。

実機は開始/更新/終了、OS上の操作、二owner共存、再起動、片側無効化/削除/復元とB保持、通常版復帰を一括する。OSの権限拒否・署名条件はFeature受付の拒否と区別する。署名差が疑われた場合は同条件の独立アプリ比較を行い、未実装をOS制約として扱わない。
