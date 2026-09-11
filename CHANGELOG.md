# Changelog

このプロジェクトの利用者に影響する変更を記録します。

## [Unreleased]

- Feature間のAppEntity/queryの名前衝突を標準の永続識別子で避ける手順とnative比較を追加。統合で消えたIntent/entity/queryや誤った参照を、単独版metadataと照合する検査ツールを提供。

- MiniAppDefinitionへ任意のonHostLaunchを追加。画面生成に依存することなく、host起動時にFeatureのnative登録処理を呼び出す。

- Background URLSessionのFeature/profile別識別子とhostイベント再接続を追加。登録解除と進行中イベントの終了を分け、重複・遅延・再入でも各OS completionを一度だけ呼ぶ。

- 通常CounterのShortcut定義をFeature側へ移し、既存の公開IntentとProvider識別子・引数・文言を保持したままhostへ合成する。

- BackgroundTasksの登録・pending取消・実行中処理をFeatureごとに所有するAPIを追加。処理ごとの通信/電源条件を保持し、期限通知と完了を重複させず、完了まで処理を保持する。

- Feature所有の標準Swift App Shortcut式を、一つのhost Providerへ合成するTuist helperを追加。単独/統合metadataの一致と、一方の寄与削除後の他方保持を検証。

- Keychainに標準SecAccessControlと操作ごとのLAContextを渡せるようにし、既存itemの保護とFeature別の取得・削除範囲を維持。実機で認証なしの読取/更新拒否と、認証後の元の値・別Featureの値の保持を確認。

- FeatureをNavigationStackのrootに置き、別Featureから詳細URLで開く際に遷移先の登録が無視される問題を修正。Feature固有のpathは詳細値だけを持ち、rootの「ミニアプリ」ボタンで一覧へ戻る。

- Web認証の提示面ごとの任意調停とFeature接続別の取消・Runtime終了処理を追加。標準ASWebAuthenticationSessionのcallback形式と提示先を維持する。
- Swift Package内のApp Intentsを標準AppIntentsPackageで接続する手順と、単独/統合metadata・所有Storeの比較検証を追加。

- Featureごとの独自URL resolverを追加。曖昧な受信先を拒否し、SwiftUIが配送したscene内で所有Featureを開き、他Featureの画面経路を保持する。
- Featureの`CFBundleURLTypes`をhostと自動合成。宣言のname/role/icon等を保持し、同名異値だけ明示resolutionを求める。

## [0.4.0] - 2026-09-11

- 通知action/foregroundの所有Featureへ、元のnative requestを復元できるsnapshotを渡す。独自userInfoやcontent/triggerを保持し、既存ハンドラーの互換性を維持する。実通知で所有者別配送と他Feature表示維持を検証。

- Featureとhostの言語別InfoPlist.stringsを合成し、app/Widgetへ別々に組み込む。言語・keyごとの衝突を明示解決でき、削除済み設定は次回生成で除去する。CIは固定文言でなく、各targetの生成設定と実bundleの一致を確認する。

- UIKitの短時間バックグラウンド実行tokenをFeature/処理ごとに所有し、個別完了・期限切れ・Runtime終了・解放時に終了するAPIを追加。他Featureのtokenを維持し、重複終了を防ぐ。OSの実行時間枠はhost全体で共有する。

- Core SpotlightのFeature別item/domain識別子と所有者限定削除を追加。native属性を保持し、Aの削除後もBの検索結果が残ることを署名付きiOS hostで検証。検索結果から所有Featureの詳細へ配送し、別Featureの経路を保持。host終了後の検索結果からの起動も検証した。
- FeatureのInfo.plist/entitlements要求をTuistで合成する仕組みを追加。異なる値の衝突を検出し、明示resolutionと限定した文字列集合の合成を提供。IPA署名もTuistの生成entitlementsを使う。

- 通常の保存操作を共有バックアップと調停する`withStoreAccess`を追加。同じFeatureの通常アクセスは並行でき、処理中の復元/snapshotと、復元中の新規アクセスを拒否する。他Featureは継続し、画面はデータ使用中を案内する。

- 復元前の停止が途中で失敗した場合の任意の回復callbackを追加。回復完了まで重複処理を拒否し、未復元と回復失敗を画面で区別する。SQLiteの実BUSY close、他owner保持、既存を含む6失敗経路で検証。

- 選択中かつactiveなsceneがある間だけ自動ロックを防ぐ任意の要求scopeを追加。非選択・背景化で解除し、復帰時に再適用。別ownerの明示leaseと複数sceneを維持し、Runtime終了後の再取得を拒否する。
- Records参照アプリで、行の文字列横の空白も詳細表示へのタップ対象に修正。

- Featureごとにsceneの活動状態・選択状態・接続終了を受け取る任意callbackを追加。既存のhost集約通知を維持し、非選択を自動的な処理終了へ変換しない。iOSの切替・背景化/復帰・他FeatureのTask継続で検証。

- 同じscene内のミニアプリ切替で、各Featureの値ベースの画面経路を保持。下部の切替メニュー、一覧からの再開、選択中だけのroot resetを追加。既存root URL/通知の動作は維持し、他Featureの経路を消さない。

- Feature/RuntimeごとのFoundation NotificationCenter購読を追加。owner限定取消、個別token取消、queued MainActor配送の抑止、購読解除とcapture解放を提供。実Foundationの9テストとiOSビルドで検証済み。並行取消とRuntime終了の保証は[接続ガイド](docs/guides/owned-notification-observations.md)を参照。

## [0.3.0] - 2026-09-10

- Feature/profile別Keychain・Cookie・HTTPパスワード資格情報の明示保存とnative URLCacheを追加。実HTTPとiOS process再起動で所有者分離を検証。
- MiniAppRuntimeの受付停止・Task取消/完了待ち・同期/非同期資源解放と、native URLSessionの終了待ちを追加。
- 選択復元のstop/apply/resume・重複予約・snapshot調停・取消/失敗段階の報告を追加。
- 通知カテゴリ合成・動的更新・owner限定削除・foreground方針・custom action配送を追加。
- host活動状態配送、idle timer lease、Feature/profile別WKWebsiteDataStore割当を追加。
- singletonのNavigationPathを廃止し、window別の状態所有とprocess通知の一件配送へ変更。
- 配布版の本体/Widgetを0.3.0 build 4へ統一。1.0は引き続き未達。

公開状態・検証範囲・既知の不足は[0.3公開記録](docs/verification/2026-09-10-0.3-release.md)を参照。

## [0.2.0] - 2026-09-09

### Added

- 添付ファイルを含むZIPバックアップ、Featureごとの選択復元、schema移行と破損時のデータ維持を追加。書出し名へ日時を含める。
- Core非依存のRecords参照Featureに、複数画面・構造化保存・添付・検索・UUID詳細ルート・記録別通知を実装。通常配布への自動追加は行わない。
- Feature所有の詳細識別子をURL・通知payloadからIntegrationへ渡す接続と、安定キーごとの複数通知IDを追加。

- 対応ミニアプリを選んでバックアップを書出し・読込み・復元する画面を追加。全選択の事前検証と上書き確認、部分失敗の報告を行う。

- FeatureごとのApp Group内ファイル保存先を提供する`MiniAppFiles`を追加。任意のデータ形式・DBで使えるURLと、Dataのファイル単位のatomic書込みを提供。

- 独立Swift Package・Root View・単独Example・UIテストを生成するTuist Feature雛形を追加。ホストへはIntegrationを明示登録する。

- GitHub Actionsで任意実行できるiOSシミュレーターの統合操作テストと、画面・実行記録の成果物を追加。

### Changed

- iOS project生成をTuistへ移行。xtool・Ruby後加工と独自Python生成を廃止し、独立Swift Package／単独appのTuist templateを追加。Counter／Reminderのホスト定義をIntegration targetへ分離。

- ミニアプリのID、表示情報、遷移先を1件のDescriptorへ統合し、通常の追加でホストのID enumや画面遷移switchを編集しない登録方式へ変更。
- Featureへ安定した保存・通知namespaceを渡す`MiniAppContext`を追加し、独立アプリの`@main`をFeatureから分離する組み込み境界を明文化。
- カウンターとリマインダーのRoot View・保存処理・通知予約をFeature側へ移し、`MiniAppContext`から保存キーと通知情報を取得する基準実装へ変更。保存キーと通知先は従来通り。
- ミニアプリの定義(ID・表示名・アイコン・Root View)をFeature側が所有する`MiniAppDefinition`へまとめ、Registryは定義の列挙だけにする。App Group解決は`MiniAppStorage`へ集約し、ID・保存namespace・通知IDの事前検査を`MiniAppValidator`で行う。
- 1.0の目標候補を、ソースコードがある独立Swift／SwiftUIアプリからFeatureライブラリと薄いAdapterへの分離支援として明確化。

### Fixed

- 通知タップ後にOSへ完了を返すdelegate処理をメインactorへ固定し、UIKitの状態復元処理が別スレッドで動いてクラッシュする問題を修正。
- Storeごとのactorだけに依存していたカウンター加算を、JibunKitCoreの共通排他処理へ接続。画面とShortcutsなど複数Storeの同時加算による更新喪失を防止。
- ドットを含むミニアプリIDの保存namespace・通知IDをエスケープし、他Featureのキーや通知prefixとの衝突を防止。既存3アプリのキーは維持。ドット入りIDを使用した派生の移行方法は`docs/updating.md`を参照。
- macOSでのFeatureテストの最低OS条件と、iOS通知取消しのコレクション型を修正。

## [0.1.0] - 2026-09-04

### Changed

- 製品名をJibunKitへ変更し、本体・Widget・App Groupの技術識別子も中立なJibunKit名へ統一。

### Added

- ミニアプリ一覧、共有保存を使うカウンター、独立保存を使うリマインダー。
- App Shortcutsから数値を加算し、更新値を返すApp Intent。
- 3サイズの表示専用Widget。
- 許可操作、予約、foreground表示、通知タップからの遷移を扱うローカル通知。
- WSLでのローカル確認、GitHub ActionsのXcode 26.6によるIPA生成、SideStore導入・更新の文書。
- ミニアプリ追加、基盤更新、貢献、脆弱性報告、公開・releaseの手順。

### Verified

- iPhone 16e、iOS 26.6、SideStore 0.6.3で、JibunKitの初回導入、build 2への上書き、署名更新後の保存値・Shortcuts・Widget・通知を確認。
- クリーンなGitHub-hosted macOS runnerで、全テスト、App Intentsメタデータ、本体・Widget、署名構造、IPA整合性を確認。

### Security

- GitHub Actionsの外部actionを固定commitへ変更し、checkout credentialを保持しないようにした。
- credential、署名・pairing材料、Apple SDK、IPAを追跡しない公開境界チェックを追加した。

### Fixed

- App Shortcutからの加算が整数範囲を超える場合、processを停止せず保存値を維持してerrorを返すようにした。

[Unreleased]: https://github.com/y-aplus/JibunKit/compare/0.3.0...HEAD
[0.3.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.3.0
[0.2.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.2.0
[0.1.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.1.0
