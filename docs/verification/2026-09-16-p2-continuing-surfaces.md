# P2-L / 0.8.2 開発・検証記録

更新日: 2026-09-16。**実装中。Swift/native CI・実機未確認、0.8.2未公開。**

対象はP2-5 / D28のLive Activities・AlarmKit。公開済み0.8.1は[出荷記録](2026-09-16-0.8.1-release.md)のまま。通常checkoutのローカル変更・Zaikoは変更しない。

## 契約と分担

[固定した契約](../delivery/P2-continuing-surfaces-contract.md)を正本とする。設計提出の提案は、この文書と契約の採否決定が優先する。設計baselineはbcfde0d、実装baselineはe46209cc5a4563b09026421dce0d1b035ddef19b。

CLI sol/lowの二レーンから、Live d731cc6 / Alarm cb00b00の初回実装を受領した。親の一括レビューで検証前の業務変更、再起動時の永続状態、未完成の通常Definition接続等を指摘し、79ce9deの共通baselineから一括修正を行った。初回設計各1提出、実装各1提出。Live修正be4451a・Alarm修正1160c2eを受領・統合済み。Live残件は親で補修し、Alarmの通知順序/購読寿命/異owner保存先拒否は同じCLI担当の2往復目bc6b99dで修正済み（理由は末尾）。[レビュー全文](../delivery/P2-continuing-surfaces-review.md)を参照。親は共通保存/直列化・通常管理/復元・host接続と統合検証を担当する。workerごとのCIは起動していない。

## 親の実装

- `MiniAppContinuingIdentity`はowner/local ID/業務世代/登録UUIDを区別する。OS対応表を業務backupと分離し、管理で業務受付を閉じた後も解除対象を読める。
- `MiniAppContinuingJournal`はowner/namespaceごとの短い同期ファイル調停とatomic保存。async OS呼出しを調停中に行わない。pendingを残し、破損を空として処理しない。実際のnative操作との途中終了回復は各adapterの責任として試験する。
- `MiniAppContinuingOperationGate`はawaitをまたぐnative操作を直列化し、closeは進行中をdrainする。管理用照合/後始末はclosedでも利用可能。process間business stateの調停は既存externalAccess/SharedStateであり、このgateで代替しない。
- Definitionのoptional `continuingSurfaces`、`effectiveExternalAccess`、`effectiveRestoreLifecycle`を通常hostへ接続。無効化/削除では解除成功後に完了へ進む。復元はgateを閉じ、既存の復元停止とOS解除を終えてから適用する。再有効化/復元resumeから活動を暗黙再開始しない。
- 起動/foregroundの再照合は画面taskと分離。enabled ownerごとに実行し、同ownerの重複taskを避ける。照合失敗は管理画面に表示し、対象ownerだけ再確認できる。無効化未完了の解除は既存管理の再試行へ残す。

## 現時点の検証

| 検証 | 結果と限界 |
|---|---|
| Python Tools試験 | 82件成功（Windows、11.771秒、追加Tools試験込み）。Swift実行検証とは別 |
| 既存操作Widget診断host生成 | 3件成功。hostがeffectiveExternalAccessを利用する変更へ既存assertionを更新 |
| `check-delivery.py` plan検査 | 25単位/12境界で成功。P2-Lの証拠合格や出荷合格ではない |
| 共通Swift試験 | `MiniAppContinuingSurfaceTests` 10件を追加。WindowsにSwift/Xcodeがなく未実行 |
| Native adapter / A/B fixture | 両review1を統合。Live親補修・Alarm review2統合済み。Swift/native検証結果はまだない |
| P2-L準備・証拠チェック | 追加Python5件成功。4モジュール組込み、欠落/再実行時の部分変更防止、support依存維持、metadata所有者混入、XCTest未実行/skip/重複/失敗の拒否。既存Simulator選択3件も再成功 |
| CI / 実機 | 本境界では未投入・未実施 |

共通Swift試験はjournal再構築・片側失敗/Bの保存bytes保持、破損/重複登録拒否、await中の直列化、close/drainと取消、OS解除失敗時のremoving維持と再試行、復元前解除/世代変更/自動再開始なし、停止失敗時の元データ保持、複数surfaceの一部失敗、close失敗時にも永続受付閉鎖、復元中の管理無効化をresumeが覆さないこと、復旧失敗時の閉鎖維持を扱う。fake成功はAlarmKit/ActivityKitの実動作の証拠にしない。

## 次の統合判定

両実装を一括レビューしてからCI用sourceを固定する。特に、同ownerが複数のattributes型を使う場合のnamespace分離、OS登録成功/保存失敗からの回復、世代/登録UUIDの両照合、解除のbounded待機、Alarm置換の部分成功、OS許可がapp単位であることを確認する。

初回予算は2run。独立/統合native build・App Intents metadata・共通試験・通常hostの管理/復元を同一sourceの並列jobへまとめ、必要な通常IPA/回帰と分担する。具体的なworkflow input/filter、変更で無効になる既存証拠、準備/uploadを含む25分見込みは提出統合後・投入前に記録する。未確定の入力を「準備済み」としてCIを起動しない。

実機は開始/更新/終了、OS上の操作、二owner共存、再起動、片側無効化/削除/復元とB保持、通常版復帰を一括する。OSの権限拒否・署名条件はFeature受付の拒否と区別する。署名差が疑われた場合は同条件の独立アプリ比較を行い、未実装をOS制約として扱わない。

## CI投入前の構成案（修正版レビュー後にsource/filterを最終固定）

- run 1: `native-surface.yml surface=continuing-surfaces ios_major=26 simulator_runtime=''`。依存のないcontinuing-live / continuing-alarm / continuing-hostの3job。独立A/B/CombinedのRelease build・app/Widget metadata差分・対象native XCTest、通常ホストの管理UIと診断IPAを分担する。`verify-continuing-surfaces.py`が各commandのlog/timingsと最終sourceを保存する。scriptは24分、jobは30分の上限。試験を省略して時間を合わせない。
- run 2: `build-ios.yml`の通常構成（simulator_tests=false、feature_validation=false、records_validation=false、その他default）。通常IPA、Foundation共通試験（今回追加のgate/journal/restoreと両coordinatorを含む）、既存の要求合成/独立package/process等。Simulator OS表示はrun 1/実機へ分け、未実施を成功としない。
- 見込み根拠: P2-W 35027469173のnative718秒/host833秒、通常版35038442208はrun6分18秒。新4Featureのcompile/metadata・追加native testを見込み、run 1はlive20分/Alarm20分/host23分（準備・upload込み）を初期見積り、run 2は10分。両runを同じSHAで並行投入すれば見込み最長23分。runner待ちは外部要因として実測する。修正版がこの量を超える場合は投入前に分割を再検討する。
- 親の注入ツールは4つの型付きFeature moduleと任意のfixture support moduleを通常hostへ追加し、既存Counter/Reminder/Widget/Share extensionを残す。全入力/anchor確認後に一括書込み、欠落時は途中のhostを残さない。実fixture 4Feature＋ContinuingAlarmSupportをtracked copyへ注入するdry runが成功。Swift検証はこれから。
- `ContinuingHostUITests`は実OS活動を開始しない通常画面/管理接続試験。無効化の保持/再有効化・片側削除/再登録と他ownerの管理状態を確認する。これはnative解除成功やOS実操作の代替ではなく、fakeの所有データ保持試験・実機のOS活動確認と合わせる。

preflight reportは最終実装のsource・確定したnative test scheme/filter・再利用証拠の差分レビューを揃えてから通す。この構成案をCI実施済みとは扱わない。

## 統合前レビューの残件と修正（2026-09-16追記）

Live review1はf745d05として統合し、8e307f1でcold handleの回復、終了中の登録を再開しないこと、同一identity/異systemIDの拒否、購読生成の重複防止/close時drain、foreground表示更新、standalone初期化を補修した。異owner journalが渡された場合も照合/解除をfail-closedとする試験を追加した。これらSwift試験は未実行。

Alarm review1は888164eとして統合した。初回のtyped package/永続業務状態/Definition/部分失敗試験は揃ったが、OS stop通知の配送前に2回照合すると受付記録を失う、closed中の照合でも購読を作る、購読生成が重複guard前に行われる問題が残った。所有権と通常終了の保証に関わるため、回数上限を理由に見逃さず、同じsol/lowセッションへ関連修正を一括返却した。新たなCIはまだ起動していない。再レビューは変更箇所と対応する試験へ限定する。

親のツールは実fixtureに合わせ、AlarmのschemeをStandaloneA/StandaloneB/Combined、host status IDをalarm-feature-a.status / alarm-feature-b.statusへ修正した。実tracked copyのhost注入で、4Featureとsupport依存、既存通常Feature/extensionを保持する構成を確認。Python全82件が成功した。生成ソースの構造確認だけでXcode build成功とはしない。

この時点の残件だったAlarm修正版は下記で統合した。次は対象sourceを固定したpreflight reportと上記2runの投入。CI完了は既存OS通知で受信し、モデルpollを行わない。

## 実機手順の準備範囲（依頼前の草案）

CI後に実際の候補IPAと表示文言へ合わせ、モバイルで一項目ずつ読める手順として確定する。現在は端末操作を依頼していない。

- Live A/B開始・各OSボタン・foreground反映、app終了後の既存登録回復、片側終了と他方の表示/業務値保持。
- Alarm A/Bの許可・固定予定/タイマー・pause/resume/標準stop配送、app終了後の既存登録回復。OSが許可しない場合はエラー/署名条件と実装不備を分ける。
- 動作中の片側無効化/再有効化、削除/再登録、業務backupの片側復元をまとめて確認。OS活動の解除、暗黙再開始なし、他方の業務値/OS活動保持を観測する。
- 通常IPAへの上書きでCounter/Reminder/既存保存値を保持。診断OS面の残存は有無と操作結果を記録し、残存を成功と決めつけない。

## CI用実装の固定前確認

Alarm bc6b99dを67ce68eとして統合し、繰り返し照合後の標準stop配送、明示再登録後の旧callback拒否、兄弟なしending拒否、異owner store不変、observer再生成制御、unknown拒否の対応差分を確認した。親で以下を追加修正した。

- AppleのAlarmConfiguration宣言にはSendable保証がないため、typed native configurationを呼出し側から転送せず、Sendableなfactory `MiniAppAlarmKitConfiguration<Metadata>`をnative request内で評価する。属性/metadata/標準設定は保持する。型宣言の再確認先はAlarmKitガイドに記録。
- Alarm support packageの参照名を明示し、checkoutの末尾名に依存しないJibunKit package名を両fixtureへ設定。
- unknown状態のpending retryをactive成功にしない。observer試験の10回yield依存をXCTestの通知待ちへ変更。native比較用JSONはsortedKeysで固定し、辞書順序による偽失敗を避ける。

投入するSwift試験は共通10件、Live10件、Alarm16件（正確な実行数・skipはCI出力で照合）。独立nativeはLive4件/Alarm2件、通常診断host UI1件。操作Widget/Control等の以前のOS実操作は本CIで再証明せず、0.8.1証拠と変更経路を照合して再利用する。通常Counter/ReminderのcontinuingSurfacesは空であり、effectiveExternalAccessは既存externalAccessをそのまま返し、restoreLifecycleの合成経路も変わらない。管理の空group解除はOS操作を行わない。共通swift全体と通常IPAは再実行する。

CIの入力・時間予算は上記2run構成で確定。独立/Combined両familyのschemeはStandaloneA/StandaloneB/Combined、native test filterはContinuingLiveActivityNativeTests / ContinuingAlarmNativeTests、通常hostはMigrationUITests/ContinuingHostUITests。preflightの完全SHA/再利用理由はローカルreportへ固定し、結果受領後に公開の証拠記録へ移す。Swift/Xcode実行前のため0.8.2完了・実機準備完了とはしない。
