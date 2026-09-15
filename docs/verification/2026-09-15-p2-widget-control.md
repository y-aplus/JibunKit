# P2-W 操作Widget/Controlの実装・検証

開始点はmain df43dac（0.8.0公開後にIssue #6を正式採用）。[開始契約](../delivery/P2-widget-control-contract.md)に設定/操作・app-extension整合・管理・OS接続・ガイドを一括した。P2-7は未完。

現在: 初期probe34975495965はsuccess。接続CI34979381516は通常job成功、native二jobが同じactor隔離エラーで失敗。識別子定数の修正をsource53e990eへ固定し、CI35022622331でnative二jobだけを再検証中。以下の投入/待機記述は履歴で、最新結果は末尾を参照する。

## 基盤実装

MiniAppSharedStateは小さなFeature所有Codable状態を選択的にapp/extensionへ共有する。owner別NSFileCoordinatorと原子的保存で、読込みから更新・受付停止・削除までを同じ調停先へ接続する。削除のtombstoneと置換世代で、古い操作の復活を拒否する。破損・未初期化を初期値で上書きしない。既存のUserDefaults/DBをこの方式へ強制せず、業務モデルはFeatureへ残す。

9件のnative試験に片側更新/別instance再読出し、変更途中throwの元byte保持、無効化/再有効化、削除/再登録と古い世代、復元世代、破損拒否、owner不一致、optional nil、未初期化拒否を追加した。別macOS processのprobeでは300並行更新、管理closeと進行中更新の順序、Aが保持中のB進行、writer kill時の未commit/lock解放、tombstoneと古い世代拒否を確認する。

通常管理・復元・Widget/Controlへの接続、Swift native実行はこの記録開始時点では未完。公開0.8.0へ追加した機能ではない。

## 最初のCIを事前probeにする理由と予算

最初の1runは、app/Widget/Controlの三入口が依存する別processの調停方式を確かめる事前probeとする。NSLockを増やすだけでは成立しない問題であり、実OSのファイル調停とプロセス終了が成立しない場合は後続三入口の保存設計を変える必要がある。in-process mockだけでは判定できない。境界の初回2run予算の1回に数え、子提出や小APIごとには実行しない。

workflow build-ios.ymlをこのbranchのimmutable SHAからdispatchする。入力はsimulator_tests=false、feature_validation=false、records_validation=true、その他default。共有全試験と新9件、macOS別process probe、通常Release/native metadata/署名/IPA/Recordsをまとめる。UIは今回は動かさず、Widget/ControlのOS成功を主張しない。

直近同等入力34967147135はrun5分16秒/job5分4秒。新試験/helper build/300 file更新と複数process起動に約2〜4分、既存準備/通常build/upload込み約8〜10分を見込み、上限目標30分へ余裕がある。job依存の追加やserial Simulatorはない。probeが失敗したらまず全ログを集め、3失敗より前でも型/ファイル調停/fixtureを切り分ける。

後続の候補runは通常接続・native metadata/独立/統合・設定/操作OS試験を一括する。具体的filterと25分以内の並列job設計をその投入前に固定し、P2全体のpreflight/evidence gateを通す。初期probeの成功だけでP2-7をcompleteにしない。probeと後続sourceが異なること、再利用する試験と差分を明記する。

ローカルではdelivery 19件を含むTools全71件が成功した（11.232秒）。このWindows環境にSwift/Xcodeはなく、新Swiftの実行はCI待ち。

## 事前probe投入

[CI34975495965](https://github.com/y-aplus/JibunKit/actions/runs/34975495965)を投入し、headSha=`b6244de6635d56969e1eceb94f35282d0dca096b`、in_progressを確認した。run数は1（初回2run予算）。GitHubのdispatch APIはSHAをrefとして拒否したため、同じSHAへ固定したbranch `codex/p2-widget-control`をrefとして使った。拒否された要求はrunを生成していない。作業継続用branchは`codex/p2-widget-integration`に分け、実行中refを動かさない。

既存のOS完了監視を登録し、一回だけqueueへ結果を送る。モデルによる定期確認やgh run watch --intervalは使わない。結果待ちの対象は上記run。製品コードはmainへ未統合で、次はこのOS調停結果を確認して通常管理/復元とWidget/Controlへ接続する。

## probe結果と通常接続

34975495965のheadShaはb6244de6635d56969e1eceb94f35282d0dca096b。runは13:31:01Z〜13:35:34Zの4分33秒、combined jobは4分24秒。共通282件（skip2、失敗0）、Records11件、SharedState9件それぞれのpassed markerを確認した。別process probeの最終出力は`passed: 300 process updates; close/write ordering; interrupted writer; tombstone/generation; B retained`。通常Release/native metadata/署名/IPAも成功。Simulator UIとWidget/Control OS操作はこのrunで実行していない。初回2run予算の1回を消費。

続く実装はoptional MiniAppExternalAccessをDefinition→通常Managementへ接続する。bootstrap、外部writeのclose/drain、無効化/削除、排他予約下の再有効化、部分的なenable失敗の登録解除を含む。SharedStateは管理受付と復元用leaseを別々に保持し、復元終了が管理の無効化を打ち消さない。復元resume失敗/プロセス終了のleaseは自動的に開かず、明示管理回復へ送る。8件の統合試験で実store、失敗/再試行、B保持、古い世代を照合する。

独立InteractiveFeatureA/Bは同じlocal IDの二項目、entity/query、Widget/Control configuration、背景実行するIncrement intentを所有する。native試験4件はquery/片側操作、設定値の共通解決/削除拒否、実Definitionの管理/選択復元/世代、保存失敗/取消を検証する。通常hostの別UI試験は管理画面で保持/削除/再登録/B保持を検証する。AppIntentsPackage/WidgetBundleによる標準登録で、既存Counter WidgetとShareは残す。

ローカルTools74件は10.983秒で成功。新規prepareの正しい接続、anchor不一致時の無変更、二重prepare拒否を含む。新Swiftはこの環境では未実行。意味のあるSwift実行結果は次のCIで記録する。

## 2回目の一括CIと実機境界

build-ios.ymlへ`simulator_tests=true interactive_widgets_validation=true feature_validation=false records_validation=false`、ui_test_filterは空、その他default。新native-surfaceの二job（interactive-native/interactive-host）と通常combinedを同一runで並列実行する。Recordsの製品/fixtureは変更しておらず独立build/UIは0.8証拠と初回probeを再利用するが、共通macOS Records試験は通常jobで再実行される。

- interactive-native: 独立A/Bと統合Release、本体/extension metadata・kind比較、hosted iOS XCTest4件。準備2分＋共通build/差分build約6分＋Simulator test4分＋証拠upload2分を見込み、14分。
- interactive-host: tracked fileだけで通常Registry/WidgetBundleへA/Bを追加。診断Release、通常管理UI1件、native metadata、Share含む署名/IPA/CRC。準備2分＋host build4分＋Simulator build/UI6分＋署名/upload2分、14分。既往のSpotlight遅延分に約2分の余裕を見込み最大18分で計画する。
- 通常combined: 共通/Records/別process試験、通常IPA/native metadata、通常UI全件（Counter/Reminder/バックアップ/管理）。buildのみ初回4分33秒にSimulator準備/全UI約8〜12分とuploadを足し18分見込み。

job間依存はなく、run全体の見込み20分（各native job上限30分、既存通常jobのtimeout45分を性能目標とは扱わない）。新fixtureなので見込みは未実測であり、CI後は実測に更新する。初回と2回目はsourceが異なり、初回probeの成功を新接続へ読み替えず共有全試験/probeも再実行する。投入sourceとpreflightは別JSONへ固定する。

実機の必須列: A/B双方のWidget/Control追加と二項目選択、選択変更とOS再起動後保持、アプリ非前景から各surfaceを操作して選択対象のみ+1、削除済み項目拒否、A無効化/再有効化・削除/再登録・片側JSON復元とB保持、世代変更後の古い設定拒否/再選択、通常IPAへの復帰とCounter/Reminder/既存Widget/Shortcut/共有の保持。端末での実タップと設定保持は直接perform試験では合格にしない。非実機結果を確認後、診断/通常IPAの同一sourceと配布ZIPを確認して手順を会話へ分割提示する。現時点ではまだ実機を依頼しない。

## 接続境界の投入

[CI34979381516](https://github.com/y-aplus/JibunKit/actions/runs/34979381516)を投入した。headShaは`4eb784d3f8f313eef9c6566f5729006e655af164`と照合済み。refは同SHAで固定した`codex/p2-widget-native`。通常combinedとinteractive-nativeの開始、interactive-hostのqueueを確認し、既存のOS監視taskを登録した。モデルの定期確認やinterval付きwatchは使わない。

[事前report](2026-09-15-p2-widget-control-evidence.json)はpreflight structure/coverageを通過。sourceと異なる旧P0/P1証拠は再利用理由を明示し、変更された管理/共通試験は次のCIを待つ。source以後のcommitはこのreportと投入記録・[実機手順の下書き](2026-09-15-p2-widget-control-device.md)のみで、実行中の製品sourceは動かさない。main・公開0.8.0は未変更。待機対象は上記CIで、実機確認を今の段階でユーザーへ依頼しない。

## 接続CIの結果と切り分け（2026-09-16 JST）

34979381516のsourceは4eb784d。通常combinedは26分30秒で成功。共通290件（skip2、失敗0）、Records11件、別processの300更新/終了/世代probe、通常Release/metadata/署名/IPA、通常UI13件、別実行のFiles JSON往復1件の成功を確認した。追加したSharedState管理8件もすべてpassed。これは通常管理/復元の共有状態接続の証拠であり、未buildのWidget/Controlの成功ではない。

nativeは6分59秒、診断hostは8分57秒で失敗。両方の原因はFeatureA/BのIncrement.performが、Widget/ControlのMainActorを継承したstatic kindをactor外から読んだこと。四つのkindを`public nonisolated static let`とし、文字列値・永続ID・Intentの実行方式・Coreの保存/管理実装は変更しない。関連するA/B全参照を確認し、片方だけ直して再投入することを避けた。新たな失敗runは1回で、3回を待たず型/actor境界まで切り分けた。

初回2run予算を消費したため、追加1runを明示する。`native-surface.yml surface=interactive-widgets ios_major=26 simulator_runtime=空`を直接dispatchできる選択肢を追加し、独立native/診断hostの二jobだけを同一runで再実行する。全metadata比較・native4件・通常管理UI1件・診断IPAまで対象を維持する。成功した通常jobは、通常Sources/Package.swift/Project.swift/Tuist/UITestsに差分がないことを確認して再利用し、26分半の通常CIを繰り返さない。

初回20分見込みに対しrun全体は約26分40秒だった。過小見積りは通常jobのstandalone Counter/backup harness/Simulator buildとFiles別試験・証拠export/uploadの直列時間を十分に足していなかったため。30分目標内だが、今後の同じ通常全範囲を18分とは見積もらない。今回の再試験は通常jobを含まず、nativeの実績準備約3分/最初のcompile約4分に、残る差分build・Simulator試験・uploadを足して並列run22分を見込む（job上限30分）。

## 修正後の再投入と通常IPA取得

[CI35022622331](https://github.com/y-aplus/JibunKit/actions/runs/35022622331)のheadShaは`53e990e18854e8cf42c5abd239bc07448b6b4059`。branch `codex/p2-widget-actor-repair`を同SHAに固定し、native-surface.ymlのsurface=interactive-widgets/ios_major=26を投入した。二jobともin_progressを確認し、OS完了監視taskを登録した。モデルによる結果pollはしない。関連local試験はhost準備3件・delivery19件、preflight構造/網羅検査が成功。実行中source以後は文書のみを更新する。

成功済み34979381516の通常IPAを取得し、2,351,018 bytes、SHA-256 `e61991a1f15fb275b030ffc1923f6ea1c541bdff9362a8f6c56f134a681de756`を確認。全entry CRC、本体/Widget/Shareの既存3IDと0.8.0/build10、3実行ファイルに新診断Widget/Control kindが含まれないことを検査した。通常コードには修正差分がないため、次の実機ではこの通常IPAへ戻す。まだ公開資産の再取得ではなくActions artifactの取得証拠である。
