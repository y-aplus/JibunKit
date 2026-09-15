# P1実機後の修正・切り分け

2026-09-15。baseline `e64d24b`、対象はP1-1/2/3。ユーザー結果と手順改善点の正本は[実機手順書](2026-09-14-0.8-device-check.md)。本書は実装/CI記録であり、実機記録を複製・移動しない。公開版0.7.0、0.8未達。

## 一括レビューと実行境界

共有文字列はplain-text適合とNSString変換可能性を同一視していた。UTF-8/UTF-16のnative data representationを読出し、既存オブジェクトprovider・ファイル・取消/drain回帰を維持する。Shortcutsの診断遅延/失敗をownerの永続storeへ移し、再生成したstoreで一度だけ消費する。管理削除で制御も消す。実機の停止操作に20秒の猶予を設けるが、OS実行での実証は次の候補で必要。

URL enqueueは現エラー番号だけでは原因未確定。Coreのエラーに安定した説明を付け、通常hostの実App Groupでprovider→enqueue→再読込を確認する。保存先の安全検査やowner admissionを根拠なく迂回しない。Widgetは配布IPAに両kind・コード・resourceが存在したので、未収録との初期推測は棄却。通常hostのgalleryと旧構成への上書きを次の検証対象にする。

今回の対象差分をまとめた切り分けCIは`native-surface.yml`の`surface=p1-input-repair`、`simulator_runtime=''`。一run内の独立incoming/intents jobで実行し、どちらかの失敗で他方を中断しない。

- incoming（見込み8分、上限30分）: 既存IncomingNativeTests全件、新規data-only UTF-8/UTF-16と実App Groupへの一括enqueue。Share ExtensionのOS UIはこれだけで合格にしない。
- intents（見込み25分、上限30分）: 単独/統合の既存metadata比較、native Intent/entity/query/管理/取消/失敗、再生成storeへの診断制御伝播。既存OS直接操作を代替したとは扱わない。

前回までの11runを維持し、今回の実機NG後は最大3runを追加予算とする。最初は上記の原因切り分け、次に結果を反映した通常/診断候補とgallery/OS受信を一括、3回目は必要な修正時だけ。成功run数を増やす目的の再実行や子CIは行わない。実機から既に原因不明が見つかったため、3失敗を待たず切り分けを先行する。

ローカルでP1 host構成18件・Intent identity tool4件が成功。workflow YAMLの解析とdiff check成功。WindowsではSwift/Xcodeを実行しておらず、下記native CIまで成功。確認済みHTTP/Web/通知とP0実機は元sourceを保持し、今後の候補への適用は差分レビューする。0.8には昇格しない。実機確認を区切りに版を進める指示に従い、P1全条件が閉じなければ次の公開は0.7.1として版変更・通常出荷検証を行う。

## 現在の到達点（34958712557確認後）

09927a6の実機で共有保存と本体内部投入がinvalidInputになった。初回owner保存先の判定修正4e6a3f4は通常273件(skip2)/native32件/完全host共有・再試行を通過し、通常/診断IPAを公開再取得で確認済み。旧判定の誤拒否はmacOSで再現、iOS26 Simulatorでは未再現。iOS27.0実機で文字列の共有保存→本体取込みが成功し、A件数1を確認した。URL/ファイルも成功しA件数3・内容3行をユーザー確認。B取込みとAの共有取消後の未取込み増加なし/A3/B件数保持も実機成功。保存後失敗/再試行の手順後に未取込みなし・A4件/B不変を実機確認。失敗直後の行保持は独立した明示観測なし。再起動後の受信A4件/B件数・内容保持と、実機Widget一覧の機能A/B表示も成功。ホームのWidget A/B描画・本体値一致・各値更新も実機成功（指定加算回数は逆、体感では即時）。機能Aの無効化/再有効化/削除/初期状態で再登録と各段階のB保持も実機成功。OS Shortcutsの20秒遅延中の取消、保存失敗時のA/B旧値保持、次回正常実行でAだけ指定量増加も実機成功。再登録後の再起動、上書き/Refresh保持は未確認。以下のrun節は当時の結果・計画を残す履歴であり、最後の節が最新の結果と待機対象。

## 残件

Widget gallery/上書き、新しい候補でOS Shareの成功/取消/再試行とShortcuts制御の確認、必要回帰・配布整合性・文書再確認。今は追加実機操作を依頼しない。過去の58件レビューはそのcommitの記録であり、本変更後の出荷確認にそのまま転用しない。

## 独立準備: gallery・次の候補

切り分けrun34881183837はsource `6dd95ccc1861d4609747d1f3f7227885e5d55109`。待機中の独立準備は別branchで行い、実行中のsourceは動かさない。

- 既存native gallery試験の操作/OCR補助を共用し、通常のCounter-only hostを同じbundle/versionでinstall/launchした後、生成P1 hostへ削除なしで置換する試験を追加。A/Bの通常保存値を取得し、gallery preview・ホーム画面の実描画と照合する。SideStoreの署名変更はSimulatorで代替できず、実機残件として保持する。
- `verify-p1-device-ipa.py`で本体/Widget/Shareの版・識別子、ZIP CRC、Widget実行ファイル内の3kind、A/Bのextension内resourceを検査。収録検査はgallery公開を保証しない。旧6beb877 IPAも検査を通り、未同梱説を否定する追加証拠となった。4つのローカルtoolテストで通常Counter-onlyやresource欠落・版/extension取り違えが失敗することを確認。
- OS ShareLink→Share Extensionの受信先→本体inbox→取込みを文字列/URL/ファイル順で通すUI試験を追加。文字列で保存後失敗/再試行による重複なし、再起動後保持とB保持を確認する。基本経路で失敗したら後続を進めずUI階層を出す。未実行のため成功証拠にはしない。
- 次の候補の本体/Widget/ShareとCI期待値を0.7.1/build9へ揃える。公開済みではなく、切り分け結果を反映してから通常/診断buildと必要回帰・実機を行う。公開tagや配布済み0.7.0/build8は変更しない。

この準備を含む次のCI入力は切り分け結果後に固定する。今回の実機結果・手順改善点を別ファイルへ移さず、再依頼の短い操作列も元の手順書へ追記する。

## 切り分け結果と次の固定境界

[run34881183837](https://github.com/y-aplus/JibunKit/actions/runs/34881183837)、source `6dd95ccc1861d4609747d1f3f7227885e5d55109` は成功。incoming25件（11.688秒）はdata-only日本語UTF-8/UTF-16、既存NSString provider、URL、ファイル、取消/drain、実host App Groupのprovider→enqueue→再読込を含む。Intentは単独A/Bと統合metadataのactions/Shortcuts一致、実行8件（0.544秒）とUI1件（43.201秒）が成功。再生成storeの診断制御/owner分離は8件内で実行済み。job時間はincoming9分48秒、intents13分16秒、合計23分04秒。

通常hostでURL enqueue失敗は再現しなかった。Share Extensionの実行環境との差は未解決なので、URLの実機不具合を修正済みとはしない。Shortcutsの別OS文脈とWidget一覧も未確認のまま。

次は一runにnormal/generatedの二jobをまとめる。`simulator_tests=true, feature_validation=true, records_validation=false, p1_device_validation=true, p1_device_http_validation=false`、generated-only/split/focused/nativeオプションはfalse。通常UI filterは空。generatedは次の4件だけを明示選択する。

- `P1IncomingUITests/testOSShareTextURLAndFileReachInboxAndRetryWithoutDuplicateCommit`
- `P1IncomingUITests/testPersistentIncomingFailureRetryIsIdempotentAndOtherOwnerRemainsIndependent`
- `P1IntentsUITests/testNormalHostKeepsDisabledAAndWritableBAcrossRelaunch`
- `P1WidgetGalleryUITests/testNormalToDiagnosticUpdateExposesBothWidgetPreviews`

normalは共通試験、通常UI/Files復元、通常IPAの0.7.1/build9・署名・metadata等の既存出荷検査を実行。前回33.82分、上限45分。generatedはhost Release build、上記4件、通常hostのcold/warm URL UIを通した後の削除なし診断host置換、診断IPA inventoryを実行（計画30分、上限45分）。ギャラリーを実行したjob自身で診断IPAも検査する。

診断Registryはfilterと独立にP1-A/P1-B/Incoming全ペアを保持する。旧HTTP/Web/通知UI8件は実装/fixtureが変わっておらず、device実績と既存CIの成功を範囲限定で再利用する。HTTP native7件はrun34816553410、Web storage/cancel/drain3件は34819734774、disable/authは34823801940、HTTP/通知UI3件は34816553410。Records実装/試験も差分なし、34806399426の成功を再利用する。native incoming/intentsは本節のrunから変更なし。版変更と新UIは今回のCIで検証し、これら再利用の成功には含めない。追加予算3runの2回目であり、残り1回を修正用に保持する。

投入前のローカル検査: P1 host/IPA tool22件、workflowコマンド転送1件、focused UI検査1件（継承解決、未知/循環/重複baseとpass欠落/重複を拒否）が成功。4 selectorの実source解決、workflow YAMLとdiff checkも成功。新galleryの共通XCTestCase継承を検査ツールへ反映し、iOS jobを始める前の誤拒否を除いた。native実績の機械可読記録は[入力切り分け証拠](2026-09-15-p1-input-native-evidence.json)。

## 候補CI34883605285: 通常成功、生成UI2件の操作を修正

source `8c54d6e1f1525cf3764dcc12f1a8fd7f30f0151a`。normal32分50秒で成功、generated28分54秒で失敗。[個別証拠と通常IPA digest](2026-09-15-p1-candidate-evidence.json)。通常の共通270件(skip2)、Records11、通常UI13とFiles JSON復元1、0.7.1/build9 IPAの本体/両extension検査が成功。通常IPAを取得しCRC/版を再確認した。まだ未公開。

生成側は通常hostのcold/warm URL UI27.044秒を通し、削除なし診断host更新後のWidget gallery・ホーム描画129.798秒が成功。OCRはA:1/B:1。永続inboxの保存後失敗/再起動/再試行も70.908秒で成功。SideStoreでのgallery問題を再現したことにはしない。

失敗は2件。OS共有はextension開始前、テストがButtonを探したが実階層では`activityCollectionView`内の`shareCell`、label `JibunKit`が表示されていた。観測したセルを選ぶよう修正する。Intent管理は`management.list`が正常に開き、上部の通知/HTTP行だけがmaterializeされていた。画面外のA操作を待つだけだったため、既存P1UIVisibilityを同試験へ共用し、状態確認も対象行を表示してから行う。native解除の状態待ちは既存完全host Web管理と同じ120秒上限、通常値読出しは15秒を維持する。製品の受付やcleanupを迂回しない。

次は追加3run予算の3回目。`generated_validation_only=true`へ変更し、完全Registryのまま失敗したOS共有とIntent管理の2methodだけを実行、診断IPA inventory/packagingを行う（計画25分、上限45分）。通常IPA・回帰、Widget gallery、永続inbox再試行、Notes単独/requirementsは本runの成功を再利用。修正はUITestとテスト補助の接続だけで、通常/診断製品コード・保存形式・識別子に差分なし。元の4件境界を縮小して未検証を消すのではなく、2成功+2再試行をsource付きで合成する。結果次第で原因を再評価し、予算だけを根拠に同じ再試行を続けない。

## 34887580504: Intent成功、OS共有の実エラーへ到達

source `340e131902a21fd6eea98a91b2e040004ba41244`、generated23分50秒。Intent管理207.791秒で成功。共有先セルの操作は成功し、文字列のShare Extensionで受信先表示前に`invalidInput`が出た。以前のNSString変換エラーから表示は変わったが、共有文字列の実動作は未解決。最初の文字列失敗で同methodのURL/ファイルへ進めず、これらの実動作は未観測。診断IPAはまだ生成していない。

追加3runを消費したため、同じ大きなbuildの4回目には進まない。次は例外として1runだけの`native-surface.yml surface=incoming-os`（計画15分、上限30分）。通常hostのtracked sourceに受信A/Bだけを接続し、実ShareLink→OS共有先→同じShare Extension→inboxを文字列/URL/ファイルの独立3methodで試す。生成Feature・独立Notes・Widget・HTTP/Web・normal Release IPAは作らない。失敗を成功と扱わず、3件の観測を次の修正判断に使う。2つのローカル構成試験、3methodのsource存在、YAML/diff checkは成功。

Debug限定でproviderの登録type、選択したdecode分岐・byte数/BOM有無、provider-load/open-inbox/read-catalogの失敗工程を出す。共有文字列・URL本文・ファイル内容は診断に出さない。Releaseのエラー形式と受入判定は維持し、文字コードの無条件fallbackや保存先安全検査の迂回は加えない。この小hostで現象が出なければ完全hostとの差を比較する。これだけを完全P1の成功証拠にしない。

この診断はP1-3.os（実機必須）の合格証拠ではないため、preflightのdevice条件は保留したまま。診断jobは別欄で入力/時間/目的を記録し、Simulatorをdeviceの代替としてgateへ登録しない。正常版とgallery、Intent管理の各成功sourceは保持する。

## 34917691331: 文字列decodeに限定、標準Transferableで修正を検証

source `193c4b26ff5c454a0d9d807958bb0b1a65e35215`、job8分01秒。文字列は`public.plain-text`1 provider、167 byte、UTF-16 BOMなしでUTF-8 decode失敗。provider-loadの段階であり、保存先やcatalogの失敗ではなかった。内部形式をアーカイブ等と断定する証拠は取得していない。URL24.223秒/ファイル31.242秒はOS共有→extension→inboxの行表示まで成功。[個別観測](2026-09-15-p1-incoming-os-evidence.json)。実機URLの以前の失敗原因は、この小host成功だけでは解決扱いにしない。

generic plain-textをUTF-8で読めない場合は、[Apple標準loadTransferable](https://developer.apple.com/documentation/foundation/nsitemprovider/loadtransferable(type:completionhandler:))でStringとして読む。型に基づく受信を標準APIへ委ね、独自のアーカイブ復号や任意型の許可は行わない。明示UTF-8/UTF-16とgenericの生UTF-8は既存data読出しを維持する。最初のcallbackが終了してから別の取消gateを作り、間の取消を確認する。データ公開やファイル寿命・owner管理は変えない。

次の必要CIは`surface=incoming-repair`、一runのincomingとincoming-osを並行実行する。incomingは既存25件+Transferable文字列/不正textの2件。従来data-only試験へgeneric生UTF-8も追加し、Apple標準register(String)で作ったproviderは日本語/改行/絵文字の完全一致を確認する。OS側の独立3件は、今回はFeatureへ取り込み後の内容一致まで検査する。前回の単なるinbox行表示と同じ成功範囲にしない。

計画はnative10分/OS10分、各上限30分。累計予算を16runへ変更する理由は、8分の診断で切り分けたdecode修正のnative/OS同時検証であり、完全P1 hostの再試行ではない。これが通った後に完全hostの未完了経路と通常/診断IPAの出荷検証をまとめる。現在は新修正のSwift/iOS実行待ちで、0.8未達・0.7.1未公開。

## 34931319103: Transferable仮説を棄却し、形式と不正入力を切り分け

source `ad3ada974c548af18357878eedeab5578fc9b730`、[run34931319103](https://github.com/y-aplus/JibunKit/actions/runs/34931319103)。[個別証拠](2026-09-15-p1-incoming-repair-evidence.json)。native27件中1件失敗（UTF-16の1バイトが空文字として受理）、OS3件中1件失敗（文字列の標準Transferableが`TransferableSupportError 0`）。URL35.019秒とファイル114.814秒はFeatureへの取込みと内容一致まで成功。nativeのregister(String)成功だけでは実Share Extensionの形式を再現できなかった。

共有文字列は348875→349176→349313で失敗が続いた。最初に小hostへ分離し、今回も全体候補の再試行は行わない。167バイトは同じ診断文字列のFoundation keyed archive fixtureのサイズと一致するが、実データの形式を断定する証拠ではない。標準Transferableへの再要求を削除し、generic plain-textの生UTF-8解釈が失敗しbinary plist headerを持つ場合だけ、Appleの`NSKeyedUnarchiver.unarchivedObject(ofClass:from:)`でNSStringに限定したsecure decodingを検証する。許可クラスの拡大、文字列への強制変換、失敗後の任意形式fallbackは行わない。UTF-16の奇数バイトは明示的に拒否する。取消gateやコピー所有権は変更しない。

追加native2件は、アーカイブした日本語/絵文字/改行の完全一致、同じheaderで始まる普通のUTF-8文字列保持、数値/配列/辞書/破損archive/非keyed plist拒否を含む。既存の明示UTF、生generic UTF-8、register(String)、取消/drain/owner試験を維持する。次の境界はnative29件と既存小host OS3件の`incoming-repair`。文字列がOSからFeature内容一致まで成功するか確認し、その後で通常/完全診断候補の必要検証を行う。現時点は修正未検証で、実機追加操作は依頼しない。

### CI待ちとqueue遅延の区別

34917691331の時刻（2026-09-15 JST）は、投入10:32:45、完了10:40:54、ローカルqueue登録成功10:41:11、会話への受信13:59:10。CI8分09秒、完了から登録17秒、登録から受信3時間17分59秒。直前ターンは10:33:41に終了しており、長い実装中のために保留されたとの証拠はない。登録後のCodex側処理が遅れた理由は未確定。これをCI実行時間や監視ポーリング時間に含めない。監視設定の変更や再送は行っていない。


## 34933726496成功: 修正確認と通常/完全診断候補への復帰

source `cad667ba7a9efdc38499accbc4297ff926bfcfb0`。[run34933726496](https://github.com/y-aplus/JibunKit/actions/runs/34933726496)は全体10分35秒、native8分54秒/OS10分26秒（並列）で成功。[個別証拠](2026-09-15-p1-incoming-success-evidence.json)。native29件はNSString限定secure復号・不正archive拒否・明示UTFの厳格性・取消/drain/owner保持を含む。OS3件は文字列39.973秒、URL44.882秒、ファイル54.201秒で、実Share ExtensionからFeatureの内容一致まで成功した。完全P1 hostと実機へは成功を拡張しない。

次の実装追加は行わず、修正済みの同一sourceから通常/診断候補を作る。一つの候補レビューの下で、既存workflowを二run並行実行する。source固定後は両runが完了するまでそのbranchを動かさない。正確な入力はローカルpreflightの`execution_inputs`に保持する。

- 通常: `build-ios.yml`、`simulator_tests=false, feature_validation=false, records_validation=false, simulator_runtime=''`。共有Swift試験、独立Package試験、build requirements、通常Release build、0.7.1/build9のIPA署名/metadata/extension検査を実行する。Simulatorを実行したとは扱わない。
- 診断: `build-ios.yml`、`simulator_tests=true, feature_validation=true, generated_validation_only=true, records_validation=false, p1_device_validation=true, p1_device_http_validation=false, simulator_runtime=''`。`feature_ui_test_filter=MigrationUITests/P1IncomingUITests/testOSShareTextURLAndFileReachInboxAndRetryWithoutDuplicateCommit`、他の任意検証は既定false。全P1ペアを登録したhostで文字列/URL/ファイルの共有、保存後失敗/再試行の重複なし、再起動後保持とB保持を確認し、同じjobで診断IPAとinventoryを作る。

### 30分以内の見込み

通常runの以前の32分50秒は、準備2分28秒、Standalone Counter3分22秒、backup harness2分30秒、通常UI12分23秒、Files復元4分26秒等の直列実行を含む。今回の通常側はbuild/試験/要件/署名に約6分、upload/setupを含め8分と見積もる。診断側は生成retry348875の23分50秒を基準に、成功済みIntent管理207.791秒を再利用し、失敗位置より先の共有/再試行を約3分追加、全体23分を見込む。準備/Release build/Simulator build/UI/IPA/uploadを含む見積りで、二runに依存関係はない。通常は25分以内、runner待ち・通知を含め30分以内を目標とする。timeout短縮では達成扱いにしない。

### 再利用の差分確認

通常成功source `8c54d6e` から候補までの製品差分は`MiniAppIncomingProviderLoader`とShare画面のDebugエラー診断。保存/復元、Counter/Reminder、Widget、Intent、HTTP/Web/通知の製品source、Registry、Project、版/識別子に変更はない。providerの変更部分は349337のnative/小host OSで実行済み、完全hostの経路とRelease buildは今回実行する。

348836の通常共通270件(skip2)・Records11件・通常UI13件・Files JSON復元1件、normal→diagnostic更新のWidget gallery/描画、永続inbox失敗再試行は範囲限定で保持する。共通試験は今回も通常buildで実行するが、通常UI/Filesは上記差分に影響されないため再利用する。348875のIntent管理成功は、同run以降にIntent製品/fixture/管理試験/host準備の差分がないことを確認して再利用する。HTTP/Web/通知/metadata/独立Featureの旧証拠も前節のsourceを保持する。新しいIPAは旧IPAのdigestや実機合格を流用しない。

この二runで累計予算を17から19へ変更する。小hostの原因切り分けは終わり、未完だった候補境界へ戻るためである。完全host共有に失敗した場合は新しい最初の失敗工程と小hostの差を調べ、成功済み通常runを自動的に再実行しない。追加実機は候補の内容・CRC・公開取得を検証してから短い手順で依頼する。

CI外のqueue遅延は別途、Codex更新後のidleスレッド保持の短縮と、未loadスレッドのqueueがresumeを待つ挙動によるものと確認した。上の時刻記録は当時の観測を保持し、CI実行時間とは区別する。


## 09927a6候補: CI・配布検証完了、実機残件待ち

[通常34942834824](https://github.com/y-aplus/JibunKit/actions/runs/34942834824)と[診断34942837167](https://github.com/y-aplus/JibunKit/actions/runs/34942837167)は同じsource `09927a6151883a3fce3e30a9c35291fe918f49af` で成功。[試験・時間・IPA digestの証拠](2026-09-15-p1-refreshed-candidate-evidence.json)。両runともdispatchから完了まで30分以内だった。

通常は共通270件(skip2、失敗0)、独立Records11件、build requirements、通常Release本体/Widget/Shareの署名/metadata/版とIPA検査が成功。完全診断hostはOS共有の文字列/URL/ファイル、保存後失敗の再試行で重複なし、再起動後保持・B保持の1methodが149.973秒で成功。小host成功だけから完全host合格を推定していない。前節で範囲を定めた通常UI/Files/gallery/Intent等の再利用も維持する。

[修正確認用prerelease](https://github.com/y-aplus/JibunKit/releases/tag/p1-device-check-20260915)へ通常/診断IPAと各ZIPを公開。4 assetすべて認証なしで再取得し、CIから取り出したIPAとのbyte一致、全ZIPのCRC、外側ZIP内のIPA一致を確認。ZIPは単一IPAを格納した標準ZIP（ZIP64不使用）。本体/Widget/Shareは0.7.1/build9。診断WidgetのCounter/A/B kindとA/B翻訳resourceもローカルで再検査した。実機展開成功やSideStore署名更新後のgalleryはこれからの確認である。

同時準備した文書branchを統合し、前候補の「実機結果待ち」を受領済みへ訂正。旧run/実機結果は履歴のまま保持する。今回の候補成立に必要な非実機検証は完了。Share、Shortcut取消/失敗、Widget一覧/管理/上書き・Refreshの残件を元の実機手順書で確認する。安定版0.7.0、正式0.7.1/0.8は未公開のまま。


## 実機09927a6: provider通過後の保存失敗

ユーザーは追加準備なしで修正診断版を起動し、受信検証Aの文字列共有から受信先Aを選択した。保存が`invalidInput`で失敗。追加件数/B状態は未確認。[原文と操作結果](2026-09-14-0.8-device-check.md#09927a6のユーザー再確認2026-09-15)を正本とする。上の「非実機検証完了」はこの追加情報を得る前の到達点であり、実機の保存成功ではない。

受信先一覧の表示はprovider decodeとcatalog読込みを通過した証拠。文字列入力ならenqueueで残る主なinvalidInput分岐は、owner保存先検査と受信type不一致。ownerはcatalogで検証済み、同じ入力typeで一覧もfilter済みなので、保存先検査を有力仮説とする。まだ実機原因を確定しない。

既存`ownerDirectory`は実在するownersRootと、未作成のowner子パスをそれぞれresolveしてprefix比較する。[AppleのNSURL仕様](https://developer.apple.com/documentation/foundation/nsurl/resolvingsymlinksinpath)では既存パスについてだけ`/private`が除去され得るため、初回保存時に同一保存先を範囲外と誤認する可能性がある。修正は実在親を一度解決し、検証済みIDの単一path componentから子を構成する。既存子はlstat相当の属性読出しで実directoryのみ許可し、dangling symlink/通常fileも拒否。不存在だけを初回保存として扱い、権限等のその他エラーを握り潰さない。安全検査や管理/削除の所有境界を無効化しない。

追加3試験はcontainer aliasからの初回enqueue・再open・A削除後の再作成/B保持、`/private`表記での未作成/既存owner、dangling owner link/通常file拒否/B保持。既存の外向きowner link拒否も維持。旧prefix比較がrunner上で失敗するかをpath非公開のbooleanで観測し、再現しなければ実機原因の実証とは扱わない。保存先拒否と受信type不一致のエラー名を分け、次の結果で仮説を区別可能にする。

この保存先修正はSwift/iOS未検証。本体の内部投入でも `failed: invalidInput` をユーザー確認。provider/Share Extensionを経由しない共通enqueueで再現するため、保存先検査の仮説を優先する。09927a6を実機合格候補として再案内しない。


### 次の固定検証境界

本体内部投入での再現を受け、同一sourceの通常runと診断runを並行実行する。前候補と同じ入力を用い、診断runに`incoming_validation=true`を追加してnative32件を並列jobへ含める。通常側のmacOS共通試験でも新規3件を実行し、macOSの`/private`表記とiOS側の結果を別々に観測する。旧比較の再現booleanがfalseなら、この環境では旧実装が初回ownerを拒否することを確認できる。修正後の成功だけで実機原因確定とはしない。

通常の前回実績6分31秒、診断16分59秒、追加nativeの前回実績8分54秒。新規3試験は短いfilesystem操作で、通常見込み9分、診断/nativeの並列run見込み20分、runner/setup/upload込み25分以内・完了目標30分以内とする。通常共通、nativeの新旧全件、完全host OS共有と失敗再試行、両Release IPAを同じ境界で確認する。修正はIncomingStoreのowner pathとエラー分類のみであり、前節の通常UI/Files/gallery/Intent等の差分再利用範囲は変わらない。

予算を19から21runへ追加。これは実機の新しい保存失敗に対する共通修正の一括検証であり、同じ仮説を変えない全CI再試行ではない。3失敗を待たず本体/拡張機能の比較で範囲を絞った。今回のCIが通る前に新候補をユーザーへ渡さない。


### iOS27.0の実機報告と追加比較の準備

ユーザーの追記で今回の実機はiOS27.0と判明。URL/ファイル共有も同じ保存エラー。メモへの出力は成功していそうとの補助観測であり、厳密な全形式検証とは扱わない。iOS26固定のSimulator成功を実機OS一致の証拠にしていたわけではないが、このmajor差を従来の比較では検証できていなかった。

[GitHubの2026-09-10発表](https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/)と[runner一覧](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)を確認。`xcode-27`はarm64/macOS27のpreviewで、確認時の一覧はXcode27 beta6、iOS27.0 Simulator。同じ27.0でも実機buildと同一と推定しない。

既存native workflowへ`ios_major=27`の明示選択を追加準備。既定26/通常IPAのXcode26.6は維持し、27ではXcode27.0とiOS27 runtimeを必須にする。OS選択に失敗して26へfallbackしない。実行したXcode/SDK/OSとsimulator一覧・選択IDをartifactへ残す。selectorの3ローカル試験でmajor分離・完全一致指定・不存在/利用不能拒否を確認した。これはiOS27上で試験した結果ではない。

4e6a3f4の進行中の二runを先に確認し、必要な修正をまとめた後で`native-surface.yml surface=incoming-repair, ios_major=27, simulator_runtime=27.0`の一runを予定する。native32件と小host OS共有3件を並列実行し、見込み各12分・run全体15分、余裕込み25分以内とする。製品の全SDK移行や全CI再実行は行わず、この比較を追加予算1run（累計22）として管理する。Xcode/SDKも変わる比較なので、差が出てもOS単独の原因とは断定しない。既存4e6a3f4のCI待ちにtokenを使ってpollせず、通知後にまとめて判断する。


### 34958710691: 通常版成功、旧保存先判定の不具合を再現

source `4e6a3f4b1358ea4859aa70cc119fc9d58f2d6dac`。[通常run34958710691](https://github.com/y-aplus/JibunKit/actions/runs/34958710691)は5分39秒で成功。共通273件（skip2、失敗0）、独立Package試験、通常Release本体/Widget/Shareの署名・metadata検査を完了。取得した通常IPAのCRCと0.7.1/build9・3bundle識別子も確認した。[個別証拠](2026-09-15-incoming-owner-path-evidence.json)。未公開であり、ユーザーへ渡す新候補はまだ揃っていない。

新規3試験と既存の外向きsymlink拒否はすべて成功。macOSの`/private`表記を使った未作成ownerでは、旧prefix比較が`legacy-contained=false`と記録された。旧検査が初回の正規保存先を拒否する不具合をrunnerで再現し、修正後の保存・再openが同じfixtureで通った。実機の失敗分岐を直接観測したわけではないため、実機原因の確定や解消とはまだ言わない。

同sourceの診断/native run34958712557はこの記録時点で進行中。結果を確認してから準備済みiOS27比較へ進む。通常IPAを再ビルドする理由は現時点でない。


### 34958712557: 診断/native成功、保存先修正版を再確認へ

source `4e6a3f4` の診断/native runは全体18分16秒で成功。native32件は失敗0、完全P1 hostのOS文字列/URL/ファイル共有・保存後失敗再試行の重複なし・再起動保持/B保持は182.857秒で成功。iOS26 Simulatorの旧判定観測は`legacy-contained=true private-spelling=false`で、macOSの`false/true`と区別する。保存先検査の不具合はmacOSで再現・修正確認済みだが、ユーザーのiOS27実機で原因確定・解消とはまだ言わない。

[保存先修正の証拠](2026-09-15-incoming-owner-path-evidence.json)。通常run34958710691と合わせ、両Release IPA、native安全検査、完全host受信経路が揃った。準備済みiOS27選択を含むbranchを統合したが、製品sourceは4e6a3f4から変更なし。ユーザーの方針に従い27固有説へ偏らず、chatの調査と修正後実機観測を優先する。27比較は未投入で、現段階の新候補配布の必須待機条件にしない。通常toolchainはXcode26.6のまま。

[再確認用prerelease r2](https://github.com/y-aplus/JibunKit/releases/tag/p1-device-check-20260915-r2)を公開。通常/診断IPAはともに0.7.1/build9、ファイル名にsource4e6a3f4を含む。旧09927a6の失敗記録は残し、再確認用と取り違えない。初回フォルダー作成を試すため、内部A/B投入を前提にせず、OS文字列共有→受信先Aを先に依頼する。追加件数やB保持は観測された範囲だけ記録する。正式0.7.1/0.8は未公開。

公開APIはHTTP500を返したが、同じrelease IDの状態を照合して重複作成せず復旧した。最終的に公開状態・source tag・4assetを確認し、認証なしの4ファイル再取得で元IPA/ZIPとの全byte一致とCRCを検証済み。外側ZIPは単一IPA、ZIP64なし。[配布証拠](2026-09-15-incoming-owner-path-evidence.json)。
