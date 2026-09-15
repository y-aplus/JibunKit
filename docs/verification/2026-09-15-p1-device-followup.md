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
