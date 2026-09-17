# P2-B: 背景実行・位置の通常接続

2026-09-17開始。baselineは0.8.3の公開後commit `23c4fd1`（製品tagはc5afccc）。対象はplan.jsonのP2-4/D15–17、P2-3/D25。親は統合・host/生成/CI・証拠を担当し、背景と位置の独立した実装を各Sol low taskへまとめて渡す。診断ごとのCIや親子の小API単位のレビュー往復は行わない。

## 共通契約

- iOS26以上。既存MiniAppID、FeatureLifetime/Runtime、launch registrations、Feature同意、管理/復元を再利用する。通常API・native構成を保ち、単一scheduler/managerへの強制移植で本来の機能を狭めない。
- OS許可・署名・背景mode・起動時登録の条件と、Featureごとの受付/所有/取消/再接続を分ける。複雑さやサンプル不足を不能の根拠にしない。Apple一次資料と現SDK宣言を確認する。
- 操作世代、停止中/許可待ち/callback遅着、部分失敗、cold起動、他ownerの非初期値保持を対象にする。管理/選択復元は業務状態を変更しても勝手にOS活動を再開しない。削除/取消が他ownerの登録や成果を消してはいけない。
- Featureは業務データとnative仕事を所有し、JibunKitは統合で失う登録/配送/所有境界を補う。nil/default値だけを検査するfake試験で完了とせず、実Feature定義を通す自動回帰と実SDK接続を含める。
- UIの単なる非表示はscene切断ではない。実sceneの活動/選択を使う。停止はnative終了とcallback配送をjoinし、古い世代の仕事を新runtimeへ配送しない。

## 背景レーン（P2-4）

所有path: 既存CoreのBackgroundTask/SharedRefresh/BackgroundExecution/BackgroundURLSession関連ファイルと対応Core tests、必要な`Sources/JibunKitCore/Background/`、`Tests/P2Background/`、`docs/guides/background-*.md`、`docs/delivery/P2-background-proposal.md`。位置・host/Project/Package/workflow/台帳は編集しない。

既存BGTask API/shared refresh journal/background URLSession registryをまず評価し、作り直さず通常入口を完成させる。refresh/processingの受付・launch・expiration・cancel・completion、cold起動、転送再接続/全event完了、重複配送・他owner保持を接続する。iOS26の通常継続処理も標準APIの可用条件に照らして扱う（特殊GPUや万能schedulerは対象外）。OS起動の非決定性をJibunKitの不具合と混同せず、手動handler呼出しをOSによる起動の証拠としない。

診断入口は`P2BackgroundProbe.definitions`、native testは`Tests/P2Background/P2BackgroundNativeTests.swift`。起動時の必要登録は既存公開hookに組込み、hostの共有変更が必要なら具体的な宣言と呼出し位置を提出する。実背景転送fixtureは既存HTTP診断を再利用できるか判断し、外部server/端末でのみ可能な条件を明示する。

## 位置レーン（P2-3）

所有path: `Sources/JibunKitCore/Location/`、`Tests/JibunKitCoreTests/Location/`、`Tests/P2Location/`、`docs/guides/location.md`、`docs/delivery/P2-location-proposal.md`。背景レーン・host/Project/Package/workflow/台帳は編集しない。

前景/背景位置、通常geofence/iBeacon、許可変更・再起動、owner別の登録/解除/配送、監視枠不足の説明を扱う。位置の標準設定や要求精度を消す一律APIにしない。iBeacon受信機材や移動など実機条件は明示し、Simulatorのmock位置を物理的な背景起動と偽らない。OS共有枠の上限を調べ、予約/登録失敗/解除で説明可能な結果を返す。大量枠の透過仮想化・予測最適化は後段。

診断入口は`P2LocationProbe.definitions`、native testは`Tests/P2Location/P2LocationNativeTests.swift`。Feature別同意とOS許可を分離する。Feature側から全appの位置登録を取消すAPIを使わず、native manager/登録ID/世代の所有を明示する。

## 一括提出・統合検証

各担当は設計判断、実装、実Feature診断、Core/native回帰、接続ガイド、合格条件とtest対応、未検証条件をまとめてcommitする。ローカルでできる検査を行い、iOSが実行できなければ未実行と記載。共有ファイルの変更要求だけを別記し、独自のCI投入/IPA公開/版更新/main変更は行わない。権限設定を変更・上書きしない。依存する重大な契約衝突だけを親へまとめて通知し、それ以外は担当内で判断する。

親は両提出を一括レビューし、必要な修正をまとめて返す。診断hostの登録/usage descriptions/background modes・通常IPA・全対象試験の実行確認を統合する。CI初回予算3run、通常25分見込み/30分目標。正確なworkflow入力/filter/再利用source/準備upload込み見積りは提出後・投入前のreportで固定する。遅くとも3失敗までに切り分ける。OS監視で完了を一回受け、モデルpollと`gh run watch --interval`は禁止。

実機は今回新しく成立するOS起動・背景/位置イベントと代表操作へ絞る。状態・失敗・管理/復元・他owner保持の組合せは自動化し、0.8.3で成功した音声/撮影全手順を繰り返さない。機材や利用条件の重要な未確定事項は、調査と代替可能範囲を示してからユーザーへ確認する。

## 実行開始と親の統合準備

2026-09-17、作成ツールのJibunKit project指定で背景・位置の2 taskを作成し、両方の実行開始と契約commit `57542e6` を確認した。以前ユーザーが確認したプロジェクト内作成方式を用い、今回はCLI workerからアプリ作成へ切り替えた。リモートでの今回の表示は未確認であり、作成成功から可視性を推定しない。作成呼出しに承認・sandboxの上書きはない。

- 背景: `01a0ad01-1515-7151-a3b1-acd08e94f1ba`、`codex/p2-background-p2-4`、Sol low。
- 位置: `01a0ad01-1516-7d12-81f4-9653270b1aef`、`codex/p2-location`、Sol low。
- 親: `codex/p2-background-location`。両レーンの提出後に以下の実接続を確認し、検証済み境界として固定する。まだCI未投入。

| 親の確認対象 | 統合時の扱い |
| --- | --- |
| cold launch | 本番`NotificationAppDelegate.didFinishLaunching`の管理受付適用→`onHostLaunch`順序を通す。診断Viewの表示だけで登録した試験をcold起動証拠にしない |
| background URLSession | 本番`handleEventsForBackgroundURLSession`→既存reconnect registryを通す。foreground download完了とOSの全event完了を分ける |
| manifest | 通常hostのID/保存先を保つ使い捨て診断hostへ両Probeを接続。usage description、background mode、scheduler identifierを実ビルドplistと照合。通常IPAに診断が混入しないことも検査 |
| 自動試験 | Core testsの再帰検出に加え、iOS専用の実Feature/native testをhost XCTest targetへ明示登録。構造化xcresultで全期待methodの一回成功・skipなしを照合 |
| native制約 | [既存scheduler比較](../verification/2026-09-11-backgroundtasks-native-pending.md)はSimulatorでnative/wrapper両方unavailable、後続はcompileのみ。[実HTTP比較](../verification/2026-09-11-background-urlsession-native-http.md)はforeground時の実転送・片側取消のみ。いずれもOS cold起動の合格へ読み替えない |
| CI見積り | 0.8.3通常job5分29秒、直近media native job12分50秒は参考。位置/背景の新しいfixtureの所要時間を未計測のまま同値としない。両レーン統合後にbuild共有・必要job・timeoutとupload込み予算を固定 |

初回の親指示は各1件。背景`5096980`、位置`ec79a62`を受領して一括レビューし、各1件の修正依頼を送った（親メッセージ計4件、修正往復は進行中）。節約効果は判定していない。

## 初回レビューとCI前修正

両提出は統合branchへ取り込んだが、製品mainへは未統合・CI未投入。以下を一括で修正する。

- 背景: Feature lifetime/管理/復元の受付とworker cleanup join、遅着launchの拒否、実際のrefresh/processing/shared refresh/HTTP操作入口、実機で観測可能な継続処理時間、continued-processing identifierの現SDK条件、既存throwing API呼出しの照合、実Featureを通す自動試験。
- 位置: runtime接続tokenと停止後操作拒否、画面なしのcold配送と管理/同意反映、破損metadataの保護、pending監視取消と遅着callback、未知identifierの他owner誤配送拒否、位置sampleの標準情報保持、検証地点/登録一覧、実Feature/native設定の試験。
- 親: `prepare-background-location-host.py`が両Fixtureを使い捨て通常hostへ接続し、`verify-media.py --surface background-location`で既存の署名/IPA/構造化xcresult処理を再利用する。workflowの`background_location_validation`で通常jobと独立実行。新しいmanifestの正確なidentifierは背景担当のSDK照合後に固定する。

親のローカル検査はhost生成/失敗前の非破壊/必須plist3件、既存media5件を通す。Swift/iOS実行やOSイベント配送の証拠ではない。通常hostのAppDelegateには既に必要なlaunch hookとURLSession callback転送があるため、二重登録を追加しない。

## 修正版の統合

背景`eff453c`・位置`38f574b`を受領。continuedの一意job/cleanup join、位置の破損保護・pending取消・SDK sample保持は改善された。背景の通常refresh/shared refresh/URLSessionには管理中の受付・停止join・再有効化の不足が残り、同担当へその範囲をまとめて再修正依頼した。親の依頼計5件、背景2往復目・位置1往復。CI前の修正であり、CI失敗回数へ混同しない。原因は初回契約の管理・寿命条件が全背景入口へ適用されていなかったこと。

親は位置のSwift条件付きコンパイル境界、古いserviceからの操作、service解放時のnative停止、破損後callbackによるwrite、選択復元中cold配送を修正した。`MiniAppDefinition.onConsentChange`と保存後の共通hookを追加し、標準管理画面が画面未表示Featureへも同意変更を伝える。拒否後cleanupが失敗しても拒否を保存したままエラーを表示する。位置固有のhost分岐は加えない。Core4件・native1件を追加し、Swift実行は統合CIで確認する。

診断plistはcontinuedの`export.*`、通常の`ordinary`とshared refreshを含む5宣言、`fetch`/`processing`/`location`へ更新した。現在地/編集可能地点と再起動後登録一覧も診断に含む。0.8.3公開済みruntimeはmainに保持し、この未検証変更は統合branchだけへpushする。

## 初回CIの固定境界

背景の再提出`64f0851`まで統合済み。親がcold転送受付拒否時のnative取消join、期限切れ後の業務開始拒否、停止中のsubmit拒否も補い、runtime sourceを`b55f87a`に固定した。背景10件・位置7件のnative試験と、Coreのcontinued6件・位置24件を初回CIで実行する。親の依頼は計5件のままで、背景2往復・位置1往復を終えた。提出は完了したが実装の合格ではない。

新しい背景接続の実HTTP試験は既存`network_server.py --run-command`を使う。serverへ到達したAを保持中に停止し、native invalidationまで待つ間もBの実ファイル保存が成立することを検査する。手動delegate配送試験とは分け、OSによるcold起動証拠とは呼ばない。ローカルでserver起動・環境引渡し・実HTTP応答を確認した。診断だけにlocal networkingのATS設定と用途説明を加える。

[投入前report](../verification/2026-09-17-p2-background-location-evidence.json)に入力・再利用証拠・予算を記録した。通常IPA/全共有試験/検索UIと、背景・位置の全17native試験/診断IPAを2jobで並列実行する。初回計画1run、予算3run、準備・upload込み25分見積り。新しいsurfaceの所要時間は未測定であり、超過・失敗時はstage別時間で切り分ける。個別XCTestにも60秒既定/120秒最大の上限を設定する。

ローカルのhost3件・media5件・workflow command1件と差分検査は成功。Swift/XcodeはWindowsで未実行。実機のOS継続処理、非決定的なrefresh起動、転送cold再接続、位置の実移動・beaconは未確認として残し、今回の自動試験成功だけでP2-3/P2-4を完了にしない。

初回[35175311988](https://github.com/y-aplus/JibunKit/actions/runs/35175311988)はsource `6f3944f`で失敗。通常jobは1分19秒、native jobは9分53秒で、両方とも`MiniAppLocationService.startUpdates/register`の戻り値未返却が原因だった。親が接続確認を追加して複数文にした際の`return`漏れ2件を`a82434a`で修正した。同じ新規API群の戻り値宣言も再確認した。native内訳はTuist生成233秒・コンパイル120秒で、試験本体とRelease生成には未到達。再試行は同じ2job/全試験の境界を維持し、予算3runのうち2回目として投入する。
