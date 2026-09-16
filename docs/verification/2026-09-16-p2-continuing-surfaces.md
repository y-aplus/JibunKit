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
| 共通Swift試験 | e6155ac / run35046154290で共通10件・Live10件・Alarm16件を含む全326件成功（既知Keychain skip2、失敗0） |
| Native adapter / A/B fixture | 両review1を統合。Live親補修・Alarm review2統合済み。Swift/native検証結果はまだない |
| P2-L準備・証拠チェック | 追加Python5件成功。4モジュール組込み、欠落/再実行時の部分変更防止、support依存維持、metadata所有者混入、XCTest未実行/skip/重複/失敗の拒否。既存Simulator選択3件も再成功 |
| CI / 実機 | 通常版35046699862成功。native35046697413はAlarm成功、Liveテスト/host診断接続のactor指定を修正中。実機未実施 |

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

## 初回CIとコンパイル修正

候補 `70c2ca406a024f53256c73a321157db489fc6e24` で[通常版35045522768](https://github.com/y-aplus/JibunKit/actions/runs/35045522768)と[native35045520639](https://github.com/y-aplus/JibunKit/actions/runs/35045520639)を投入し、両head SHAを照合してOS完了監視を登録した。preflight構造/網羅検査は通過。native側の3jobは独立で、通常版失敗によってcancelしない。

通常版はshared Coreコンパイルで失敗（job01:48:40–01:50:09 UTC、89秒）。実行テスト・IPA buildへは未到達。全エラーを重複除去し、次の3点を確認した。

1. 親のforeign journal拒否追加時の置換がJournalAccess.initまで及び、coordinator専用readOwnedをscope外で呼んでいた。アダプターは元のjournal.readへ戻し、owner検証はcoordinator内に維持する。
2. reconcileで組み立てた可変keptをSendable closureがcaptureした。確定した不変snapshotを保存closureへ渡す。
3. Alarm observerのnested escaping closureでnativeに明示selfがなかった。captureを明示する。

修正はCI実行中branchを動かさず `codex/p2-live-ci-repair` に保存。同種の新規coordinator/journal closureと共通テストの接続を点検した。ローカルdiff check成功、Swift成功はまだ主張しない。native側の全結果も揃えて一括修正するため、この3点だけで再dispatchしない。現在の既知失敗は通常版1run/コンパイル1回であり、native結果は未確定。

## native初回結果と再実行境界

35045520639も70c2ca4で完了し、3jobすべてが上記と同じCoreコンパイル3点で停止した。別のiOS固有エラーはログに出ていないが、未到達部分があるためSDK全体のコンパイル成功とはしない。liveはStandaloneA build、AlarmもStandaloneA build、通常診断hostはJibunKit-App buildで失敗。Tuist生成/依存解決へは到達・通過した。native XCTest/host UI/IPAは未実行。

実測はAlarm7分10秒、Live6分29秒、host5分17秒。初回は通常版89秒を含め4job計20分25秒。全4jobが同じ未修正sourceの一括投入で失敗したもので、同じ修正を3回試したわけではない。2つのrunの全エラーを照合し、原因をec24756の3修正へ限定できたため、盲目的なtimeout変更や専用probeの追加はしない。

初回予算2runから追加2run（累計4run）を使う。理由は新Coreのcompile不備で全検証が未到達のため。修正はread closureの接続/不変capture/明示selfだけで、受入条件・操作assertion・期待値を緩めない。native3jobと通常版を同一の新SHAで、初回と同じworkflow入力/filterにより並列再実行する。成功済みのnative/IPA証拠はまだないため、今回のCore変更の影響を受けない旧P0/P1証拠以外は再利用しない。

見積りは初回と同じnative最長23分/通常10分、nativejob30分上限。初回実測の生成/初期compileに最大7分を要した点を踏まえ、成功後は残りのnative tests/IPAまでのtimingsを照合する。同じ受入条件でさらに失敗した場合は、今回の3点との同一性/初めて到達した工程を切り分けてから再実行する。

## 2回目の通常版結果・SDK隔離の修正

[35046154290](https://github.com/y-aplus/JibunKit/actions/runs/35046154290)はe6155ac88c55c42d2d31a42ba359311b77334112。job4分03秒でiOS Release buildに失敗した。前回3点は解消し、共通326件（skip2・失敗0、うち新規共通10/Live10/Alarm16）、Records11件、Feature build requirements、独立package、backup memory別process、Tuist生成は成功した。native UI/IPAはまだ未完で、run全体を成功扱いしない。

新しい失敗はActivityKitLiveActivityDriverのSDKオブジェクト隔離。Activity<Attributes>をdiscovery taskからactor.watchへ渡し、さらにTaskへcaptureすることをSwift6が拒否した（3診断、同じ原因）。fake coordinator試験ではSDK型を使わないため検出しない。Activityへunchecked Sendableを付けず、watchにはString IDとSendable continuationだけを渡し、活動の列挙・SDKインスタンス取得・async sequence消費を監視Task内へ揃える。終了済taskを一覧から除き、cancel後に遅れてwatchが届いても再生成しないclosed flagも加える。

今回も進行中sourceを動かさず、修正はcodex/p2-live-sdk-repairへ保存。35046152156のnative3jobが終わるまで追加dispatchしない。Core compile阻害を直した後に初めて到達したiOS SDK段階での失敗であり、前回と同じエラーの再現ではない。次の結果に同じSDK隔離の指摘が残るなら、追加の全CI前に標準ActivityKitの最小async sequence比較へ切り分ける。


35046152156の3jobもe6155acで完了し、同じActivityKitインスタンスのactor/Task間転送エラーのみだった。Alarm3分52秒、Live5分24秒、host5分58秒。2回目の4job計19分17秒。初回からの累計は4run・39分42秒。native comparison/XCTest/host UIはまだ未到達。

af484a1でSDKオブジェクトの転送を除去したため、追加2run（累計6run）を初回と同じ入力/filterで実行する。Swift6の安全性検査は維持し、unchecked Sendableやpreconcurrencyで隠さない。e6155acの326件/Records11件等の成功証拠は保存するが、通常workflowはIPAのbuild/signing/metadataまで再検証するため既存の短い共通試験も再実行する。native最長23分・通常10分の見積りを維持。3回目の一括検証で再び失敗した場合は、初回Core接続/2回目SDK隔離の両ログと比較し、全再実行の前に到達工程・最小の直接SDK/fixture比較・再利用可能jobを再評価する。

## 3回目・通常版成功と取得IPA

[35046699862](https://github.com/y-aplus/JibunKit/actions/runs/35046699862)は`b1d379bf5179564230299d02295d3c130efd7866`で成功。通常job3分53秒。shared326件（既知Keychain skip2・失敗0、新規common10/Live10/Alarm16を含む）、Records11件、要求合成/独立package、incoming別process200commit・SharedState別process300update、通常Release app/Widget/Share、署名/metadata、IPA CRCが成功した。ActivityKit SDK隔離の修正で通常iOS buildまで通過した。

artifactをローカルへ取得してIPA全entry CRCを再検査し、実際のInfo.plistから本体com.jibunkit.app・Widget・Shareの3IDと0.8.1/build11を確認した。IPAは2,874,006 bytes、SHA-256 `a72dbcce4f57959a41af7188cf4ecd3014032067dacff8c949b58b7183115de1`。実機確認後に版を進める運用に従い、現段階の診断比較用buildは既存版を維持する。これは0.8.2公開・実機完了を意味しない。

35046697413のnative3jobは完了通知待ち。通常版成功を独立A/B/Combinedのmetadata、診断host UI、OS活動の実動作の代替にしない。実機へ案内する前に残るnative証拠と診断IPAを照合する。CI用branchは固定し、この記録はcodex/p2-live-evidence側へ保存する。

## 3回目・native結果と切り分け

[35046697413](https://github.com/y-aplus/JibunKit/actions/runs/35046697413)はb1d379b。Alarm job7分06秒で成功、Live9分25秒/host4分47秒で失敗。取得artifactのresult.jsonは全て同SHAで、Alarmだけpassed=trueと照合した。

- Alarm: 独立A/B/CombinedのRelease app/Widget、app・Widget各2定義のmetadata比較とWidget→app対応、native XCTest2件が成功。OSで鳴る/止める操作は未確認。
- Live: 独立A/B/Combined Release app/Widgetと各2定義metadata比較は成功。native XCTestのcompileで、MainActorテストから非isolated補助関数へclosureを送る箇所が拒否された。実行テスト0件であり4件成功とはしない。
- 通常診断host: 実Feature factory参照のMainActor属性をContinuingProbe.makeの引数型が落としていた。4factory全て同じ1つの補助関数で失敗。診断IPA/UIは未到達。

3回失敗時の切り分けとして、初回Core接続不良→2回目SDK転送→今回は診断/テストのactor型という異なる阻害工程を全ログで照合した。現在の製品Coreとnative adaptersは通常IPA、Live/Alarm全Release、Alarm nativeでcompile済み。Alarm nativeの@MainActorテストは同じDefinition factoryを直接呼んで成功しているため、factory内部ではなく型を落としたhost helperへ原因を限定できる。Liveの実production service/buildも成功し、未修飾テストhelperへ渡す時点だけで失敗する。新しい最小probeを別CIで作らず、これら既存の直接呼出し成功を比較対照として使う。

host factory引数へ@MainActor @Sendableを保持し、Live async assertion helperとそのclosure引数を@MainActorへ揃えた。actor検査を無効化しない。これ以外のSources、package、Alarm fixtureに変更なし。

追加は1run（累計7run）に削減し、`native-surface.yml surface=continuing-live-host ios_major=26 simulator_runtime=''`の独立2jobだけを実行する。新choiceは既存Live/host verifierと同じ入力・assertionを使い、Alarmを除外するだけ。Live20分/host23分、並列最長23分見込み。通常版/Alarmはb1d379bの成功を差分レビュー付きで再利用する。ローカル準備/証拠checker5件、Simulator選択3件、YAML parse、diff checkは成功。累計6runの実行済job時間は64分53秒。
