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

次の変更ではMiniAppRestoreFailureに停止／適用／再開／適用と再開の両方のstageを保持し、BackupScreenで区別する。適用成功・再開失敗を単なるデータ復元失敗と表示しない。後続Feature未変更の報告を維持する。unitは各stageと両失敗時の後続未実行を検証する。CI待ちであり、画面での失敗経路の実行証拠はまだない。

## 復元予約と失敗段階

[34385366877](https://github.com/y-aplus/JibunKit/actions/runs/34385366877)で失敗stageのunit、選択復元UI52.567秒、generated host全12件が成功した。失敗メッセージの実画面テストは未実施。

次の変更はプロセス共通のMiniAppRestoreCoordinatorをplan.applyの既定経路に接続する。全選択ownerをstop前に予約し、重複を含む要求は誰も変更せずConflictとして拒否する。成功・throwとも予約を解除する。重ならないplanは並行実行できる。unitはcontinuationでAを停止中に固定し、A+Bの拒否、B単独の進行、A完了後の再実行、失敗後の予約解除を確認する。固定sleepは使わない。CI待ち。

これは同一プロセス内の復元同士の調停。通常の書込み停止はFeatureのrestoreLifecycle、extensionなど他プロセスとの排他は保存層が引き続き担う。予約はplan全体の終了まで保持する。独自coordinatorを渡す場合、その利用者同士だけが調停対象となる。

## 同時復元の確認と画面失敗経路

[34388749311](https://github.com/y-aplus/JibunKit/actions/runs/34388749311)（source `5991836`）で重複拒否・非重複並行実行・成功後再予約・失敗後予約解除のunitと通常IPAビルドが成功した。

次のiOSテストではCI専用fixtureの起動環境から停止失敗／適用後失敗／再開失敗／適用と再開の両失敗を注入する。製品BackupScreenの確認操作とエラー表示、Aのデータと実行状態、Bの元データとTask継続を四経路とも検証する。適用失敗は変更後にthrowし、部分変更を警告する表示と実状態を照合する。環境入力はCI fixture内のみで通常IPAに含めない。実FeatureのDB復旧をこの試験で確認したとは扱わない。CI待ち。

## 画面失敗経路の結果と取消境界

34389357592 attempt 1で復元失敗4経路184.205秒が成功。Records添付のFiles選択完了待ちでrunは失敗した。同一source `873e031` のattempt 2は全体成功し、復元失敗4経路138.626秒、Records添付69.986秒で成功した。添付の不安定性の原因は未確定で、修正済みとは扱わない。

次の変更では予約取得前にTaskの取消を確認し、取消済みなら停止・適用を始めない。開始後の取消は実処理の終了まで予約を保持する。取消要求を受けただけで予約を解除すると、まだ書込み中の処理と次の復元が競合するためである。開始後の適用が取消を無視して正常完了した場合は成功として返す。unitはcontinuationで各境界を固定し、未開始時の副作用なし、開始済み処理の取消後も重複拒否、終了後再予約を検証する。CI待ち。

## 複数ownerの取消

34412140159（source `c67e331`）で開始前取消・取消後も実処理完了まで予約保持・予約再利用のunit、通常IPAビルドが成功。次の変更では各ownerへの着手前にも取消を確認する。A適用中に取消された場合、Aのresume完了を待ち、Bのstop/apply/resumeは呼ばず、completed=[A]・failed=B・stage=cancelledBeforeStartとして返す。これはAの成功を失わず、B以降が未変更であることを区別するためである。continuationで順序を固定するunitを追加しCI待ち。最後のownerが取消を無視して正常終了した場合は引き続き成功扱い。

## 書き出しと復元の競合

34412585049（source `fabb6d9`）で複数owner途中取消のunitとIPAが成功。次の変更はJSON/file providerのexportEntryにも同じ予約を適用する。復元中の読み出しと、snapshot作成中の復元開始を拒否する。unitはJSON exportを停止中に復元拒否、復元を停止中にJSON/file双方のcallback未実行と出力先未作成を確認する。CI待ち。

予約は各Featureのsnapshot作成完了まで。複数Feature共通の一点時刻snapshotや、Filesへの保存先選択中の予約保持は約束しない。生のexport closureを直接呼ぶ場合は調停を迂回するため、hostはexportEntryを使用する。通常の編集とのsnapshot整合性はproviderが担い、別processとの排他は引き続き未完である。

## snapshot予約の終了条件

34413012454（source `34f233b`）でexport対restoreの競合unitとIPAが成功。追加unitでは、不正ownerのJSON出力・ファイル出力callbackの取消エラー後に予約を再利用できること、Aの出力中でもBの出力が進むこと、Aの取消要求後もcallbackが終わるまで復元を拒否することを検証する。ZIP exportにもcoordinator引数を追加し、内部のJSON/file双方へ同じ値を転送する。CI待ち。

## ZIP公開APIの結合検証

34413399441（source `baf23c8`）でsnapshot予約の異常終了・取消・別owner継続のunitとIPAが成功。次の結合テストは独自coordinatorで復元を止め、ZIP exportのJSON/file両経路が同じ予約に対してConflictを返すことを検証する。解除後は両形式でZIP書出し・読込み・復元plan実行まで確認する。これを含めてiOS回帰を実行する。CI待ち。

## 全体回帰の時間上限と旧表示テスト

34413746215（source `d97ee2e`）は45分のjob上限でcancelled。ZIP公開API結合unit0.031秒、生成host回帰（復元失敗4経路172.115秒、選択復元63.151秒、Web保持92.670秒を含む）は成功。通常hostでBackupRestoreUITests.testApplyFailureReportsCompletedFeatureが変更前の「リマインダーで失敗」を期待して失敗した。現在の段階別表示に合わせ、対象名・適用失敗・部分変更の可能性・後続未変更を検証するよう更新。

Files roundtripの後続試験は時間切れで未完、Recordsは未実行。次はfeature_validation=falseで通常hostとFiles回帰を実行し、成功済みの生成host検証を重ねずに未完部分を確認する。上限超過を全体成功とは扱わない。
