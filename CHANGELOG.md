# Changelog

このプロジェクトの利用者に影響する変更を記録します。

## [Unreleased]

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
