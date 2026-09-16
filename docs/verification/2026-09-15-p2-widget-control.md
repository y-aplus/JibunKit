# P2-W 操作Widget/Controlの実装・検証

開始点はmain df43dac（0.8.0公開後にIssue #6を正式採用）。[開始契約](../delivery/P2-widget-control-contract.md)に設定/操作・app-extension整合・管理・OS接続・ガイドを一括した。P2-7は未完。

現在: CI35027469173（e984d44）はnative/診断hostの両jobが成功。通常job34979381516は差分確認して再利用。確認用prereleaseを公開し、全4assetの無認証再取得・完全一致/CRCを確認。一括実機確認も完了し、0.8.1/build11の出荷CI35038442208待ち。公開/main統合と1.0全体は未完。以下の待機記述は履歴。

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

## 35022622331の結果と次の一括修正（2026-09-16）

run全体17分28秒、native6分46秒、診断host17分16秒で失敗。前回のactor隔離エラーはhostのRelease/Simulator buildで解消。nativeはStandaloneAWidgetのWidget/WidgetBundleが見つからず、SwiftUI importが欠けていた。同じ構成のA/B/Combined全3箇所を修正した。CLI sol/low workerの提出0c97412を親がレビューし27c77d3へ統合。owner別actions/entity/queryのmetadata確認と各native試験の1回成功条件も確認した。worker自身のCIはなく、親への追加レビュー往復も行っていない。

hostは最初の無効化で「無効化が未完了。新しい起動は停止しています。」「通知・検索などの登録解除」を表示し、20秒の期待値待ちで失敗した。SharedStateの受付停止より後まで進んだ証拠であり、ラベルの綴り違いではない。今runにOS service logはなく、通知とSpotlightのどちらで待ったかは未確定。過去P1の解除約63秒成功/120秒超過失敗の両記録を照合した。既存P1と同じ120秒を無効化・削除だけへ適用し、native操作のwarmup/retry/省略は行わない。無効状態のまま再起動して保持/B有効を確認する。XCTest側の開始/経過時刻と、通知/SpotlightのOSログ・添付exportを追加した。待機延長だけで製品の遅延原因が直ったとはしない。

修正sourceはe984d44fbae1946720f2d43f3ee776e2f25c20f1。Tools全77件、workflow YAML parse、diff checkが成功。WindowsではSwift/Xcodeは未実行。初回2run予算に対する4run目の例外を事前reportへ記録し、native-surface interactive-widgets/iOS26のnative4件/hostUI1件/診断IPAをまとめて実行する。見込み25分、各job上限30分。通常製品pathは4eb784dと同じなので成功済み通常job/IPAは再利用する。さらに解除が失敗した場合は採取したOSログで切り分け、上限だけを再び延ばさない。

[CI35027469173](https://github.com/y-aplus/JibunKit/actions/runs/35027469173)を凍結ref `codex/p2-native-management-repair`で投入し、headSha e984d44との完全一致と両job開始を確認した。OS完了監視を登録済み。現時点の待機対象はこのrunで、ユーザー承認・実機操作はまだ求めない。

## 35027469173成功と実機配布（2026-09-16）

source e984d44、全体14分05秒（見込み25分）、native11分58秒・host13分53秒。Xcode26.6（17F113）、macOS26.6.2、iOS Simulator SDK26.5。独立A/B/CombinedのRelease build、app/extensionのactions/entity/query10定義と識別子/参照の比較、native4件（0.746秒）が成功。通常hostでは管理UI1件（202.283秒）が成功し、無効化・無効状態の再起動保持・有効化・項目保持・削除/再登録とB保持を確認した。直接performを実OSのWidget/Control操作成功とは扱わない。

初回無効化のUI期待値待ちは88.348秒、削除は14.485秒。OSログでは21:55:54.748 UTCにpending通知取得を開始、.760にdelivered取得完了、.763に0件削除、.771にSpotlight domain削除へ入った。21:56:03.051にIndexAgent接続中断が記録され、searchdはPID2677から14368へ変わり21:56:04.919に同じappの削除要求を受けている。通知後のSpotlightサービス処理に遅延があることを支持するが、88秒全体がcallback時間だとは断定しない。OS内部の原因/実機でも発生するかは未確定。P1同様に虚偽の解除完了や処理省略をせず、実機の初回待ち時間を確認する。

診断IPAは2,598,654 bytes、SHA-256 `456e2ca666b0d709b527d8fa9cb1aa19d038191b7ebf818c3787c71d3534608c`。CIの署名/metadata/CRC検査に加え、取得後の全entry CRC、既存本体/Widget/Shareの3ID・0.8.0/build10、Counter kindとA/B各Widget/Control kindを照合した。通常IPAは4eb784dの2,351,018 bytes/SHA e61991a1…を再利用し、診断kind非混入と通常source差分なしを確認した。

[実機確認用prerelease](https://github.com/y-aplus/JibunKit/releases/tag/p2-w-device-check-20260916)のtagはe984d44。診断/通常それぞれのIPAと単一IPA入りZIPを公開し、4ファイルすべてHTTP200で無認証再取得・元byte完全一致・CRCを確認した。ZIP64なし。既存release/tag/assetは変更していない。正式版とmainは未更新。実機手順は[こちら](2026-09-15-p2-widget-control-device.md)。実機確認後に版を進める。

## 一括実機完了と0.8.1候補

[操作別結果](2026-09-15-p2-widget-control-device.md)に全工程の確認をまとめた。Control設定は編集状態で開き、コード修正なしで成功。実機の無効化はほぼ即時。本体の表示は手動再読込み前に反映したが、一般的な即時更新保証にはしない。選択/管理/復元/更新保持と通常復帰まで確認済み。0.8.1への版更新と公開は[出荷照合](2026-09-16-0.8.1-release.md)に分ける。
