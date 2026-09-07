# ミニアプリの追加

JibunKitのミニアプリは、ビルド時にSwift Packageへ組み込む。組み込み単位は`@main`を持つ独立アプリtargetではなく、SwiftライブラリtargetとしてコンパイルできるFeatureである。動的プラグイン、任意のIPA読込み、ミニアプリストアは対象ではない。

リマインダーが、保存・画面・通知を持つ最小の実例である。ID、表示名、アイコン、遷移先はFeature側の1件の定義へまとめ、ホストの一覧や画面遷移へ個別のswitchを増やさない。

## 通常の画面を追加する

### 雛形から始める

macOSのTuist 4.207.0で次を実行する。Windowsでは同じファイルを手動作成してActionsで検証できる。

```bash
tuist scaffold feature --name Notes
tuist generate --path Modules/Notes --no-open
```

`Modules/Notes`へ独立したSwift Package・Root View・薄いExample App・Project.swiftを生成する。`NotesExample` schemeだけで試用でき、JibunKitCoreに依存しない。名前はSwift型名として使える英数字（先頭大文字）にする。既存フォルダには生成しない。これは雛形生成であり、既存アプリの自動変換やホストへの自動登録ではない。独自Pythonのdry-run／衝突検査は廃止し、差分確認と以下の明示登録へ移行した。

JibunKitに組み込むには次を行う。

1. ルート`Project.swift`のpackagesへ`.package(path: "Modules/Notes")`を追加。
2. JibunKit-Appのdependenciesへ`.package(product: "NotesFeature")`を追加。
3. ホスト側の薄い接続ファイルで`import NotesFeature`し、`MiniAppDefinition(id: MiniAppID("notes"), title: "日記", systemImage: "book") { _ in NotesRootView() }`を定義してRegistryへ列挙する。
4. `tuist generate`とビルドで確認する。FeatureのテストはそのPackageで実行する。

Featureをroot Package内に置く方式も使える。その場合はPackageのtarget・library productと、Projectのproduct依存を明示する。既存Counter／ReminderはFeatureとIntegrationのtargetを分け、IntegrationがMiniAppDefinitionとbackup登録を所有する。単独appはFeatureだけを参照する。既存StoreはJibunKitCoreの保存APIを使うが、新しいFeatureへこの依存を強制しない。

### 手動で追加する・生成後の内容を実装する

1. `Sources/<Name>Feature`へ保存・更新処理、`MiniAppContext`を受け取るpublicなRoot View、ID・表示名・アイコン・Root Viewをまとめたpublicな定義を置き、`Package.swift`へライブラリtargetと本体からの依存を追加する。StoreのUserDefaults解決は`MiniAppStorage.sharedDefaults`を使い、保存キーはContextから取る。独立版も維持する場合、独立版の`@main`は別のapp targetへ残し、Feature targetへ含めない。既存コードとの変換が必要な場合は、Feature側に薄いAdapterを置き、そのRoot Viewから呼ぶ。
2. `Sources/JibunKit/MiniAppRegistry.swift`の`all`へ定義を1件列挙する。ID・表示名・アイコン・destinationをRegistry側に書かない。IDは小文字英字で始め、小文字英数字、`.`、`-`、`_`だけを使う。IDは保存namespace、通知request ID、通知payloadの遷移先になるため、公開後に安易に変更しない。
3. `MiniAppValidator.validate(ids:)`をテストから呼び、ID・保存namespace・通知request IDの不正と衝突を事前確認する。Storeの保存キーはstatic定数ではなくContextから初期化したinstance値にし、通知予約のrequest IDとpayloadもContextから取る。別ミニアプリのStoreやキーへ依存させない。
4. `JibunKitCoreTests`でID、保存namespace、通知request IDを、統合テストで同じUserDefaults suite内の保存値が互いを変えないことを確認する。

接続層（Integration targetまたはホスト側の接続ファイル）に置く定義の例:

```swift
public enum ReminderMiniApp {
    public static let definition = MiniAppDefinition(
        id: .reminder,
        title: "リマインダー",
        systemImage: "bell"
    ) { context in
        ReminderRootView(context: context)
    }
}
```

```swift
static let all = makeRegistry([
    CounterMiniApp.definition,
    ReminderMiniApp.definition,
])
```

通常の画面追加で`MiniAppID.swift`、`MiniAppListScreen.swift`、`AppNavigation.swift`を編集しない。ミニアプリ固有の画面や通知予約処理を`Sources/JibunKit`へ追加しない。JibunKitが受け取るのはFeatureライブラリであり、既存Xcode app targetのfileを名前や条件コンパイルで自動除外する変換器ではない。

リマインダーでは、`ReminderStore`が`reminder.message`だけを扱う。カウンターの`counter.value`とは同じApp Group内でもキーが分かれ、統合テストで独立した保存と再読込みを確認している。

## ローカル通知も追加する

通知の受け取り口はホストに1つだけ置く。既存の`NotificationAppDelegate`が起動時にnotification centerのdelegateを設定し、通知payloadのミニアプリIDを`AppNavigation`へ渡す。新しいミニアプリのためにapp delegateを増やさない。

通知を予約する側では、次を守る。

- request IDとpayloadは定義から渡された`MiniAppContext.notificationRequestIdentifier`と`notificationUserInfo`を使う。
- 通知許可は、通知を使うと利用者が選んだ操作の中で確認・要求する。アプリ起動時には要求しない。
- 拒否はクラッシュや全画面エラーにせず、そのミニアプリの通常操作を続けられる結果として扱う。
- 未登録・古い・不正なpayloadは別ミニアプリへ推測で遷移させず、一覧へ戻す。
- `UNTimeIntervalNotificationTrigger`の時刻は予約条件であり、正確な表示時刻を保証するものとして説明しない。

リマインダーの`ReminderNotificationScheduler`はFeature側にあり、Root Viewから渡されたContextのrequest IDとpayloadを使う。画面の「10秒後に通知」からだけ許可を要求する。foregroundでも通知を表示し、通知タップは同じdestination mappingでリマインダー画面を開く。

## WidgetやApp Intentを追加する場合

通常画面の追加だけなら、Widget extensionやApp Intentの宣言は不要である。

Widgetを追加する場合は、別extension target、Widget bundleへの登録、extensionの`Info.plist`、本体と同じApp Group entitlement、IPAへの組込み検査が追加で必要になる。共有値はfeatureの同じStoreを通して読む。Registryから生成されないため、Featureが所有する安定IDから同じContextを生成したshared Storeを使う。現在のカウンターWidgetが実例である。

App Intentを追加する場合は、Intent型と`AppShortcutsProvider`へのphrase登録に加え、Xcodeが生成するApp IntentsメタデータをIPAへ含める必要がある。Tuistのapp target内で宣言してXcodeに生成させ、Shortcuts実機確認用IPAはGitHub ActionsのmacOS／Xcode 26.6経路で生成する。現在の`AddCounterValueIntent`と`JibunKitShortcuts`が実例である。Intentからも同じshared Storeを使う。

## 検証

変更後は次を分けて確認する。

1. WSLの`swift test`でfeature処理、ID衝突、独立保存を確認する。
2. Tuistで生成したworkspaceをXcode／Actionsでビルドし、WidgetとIPAを検査する。
3. App Intentを含む場合はGitHub Actionsで公式メタデータ入りIPAを生成する。
4. SideStoreで更新インストールし、一覧からの起動、保存値の独立、通知許可の拒否、通知予約、foregroundと終了状態からの通知タップを実機で確認する。

ビルド成功、SideStore導入成功、各system surfaceの動作成功は別々の証拠として記録する。

## 基盤が保証する保存の境界

`MiniAppContext.storageKey(_:)`はID中のドットを`%2E`へ変換してからキーを連結する。例えば`zaiko.backup`の`latest`は`zaiko%2Ebackup.latest`となり、`zaiko`の`backup.latest`と衝突しない。通知request IDにも同じnamespaceを使う。通知payloadには元のIDを使う。

同じ保存値を複数のStoreから更新する場合、読み取り・計算・書き込み全体を`MiniAppStorage.withExclusiveAccess { ... }`へ入れる。CounterStoreが使用例。これはプロセス内の全利用者に共通する同期的な排他処理であり、各Storeのactorが別でも更新を直列化する。全writerがこの境界を使う必要がある。closureは短い同期処理にし、入れ子に呼び出さない。失敗時のrollbackやプロセス間の排他は提供しない。現在のWidgetは読取り専用であり、別プロセスからの書込みを追加する場合は保存方式も再設計する。

JibunKitはFeature同士の識別・保存先の分離と共通APIの契約を担当する。Featureの入力検証、バックアップ形式、通知する条件など、そのFeature固有の正しさはFeature側で担保する。基盤が不正な実装を自動補正する契約にはしない。

## 画面とホストの境界

一覧からFeatureを開く最外層の`NavigationStack`、一覧へ戻る操作、標準の画面タイトルはJibunKitが所有する。FeatureのRoot Viewはそのstackの内容を返し、もう1つのroot stackを入れない。Feature固有のpush先は固有のroute型で宣言してよい。設定・編集など別のsheet内には、そのsheet用の`NavigationStack`を持てる。

同じRoot Viewを単独アプリでも使う場合、単独版のApp Shellが`NavigationStack { FeatureRootView(context: ...) }`で包む。JibunKit内のためだけに独立版の起動・画面構成をFeatureへ埋め込まない。

foregroundの通知はホストがbanner・通知センターのlist・soundを指定する。表示内容や予約条件はFeatureが持ち、タップ後の入口はContextのpayloadを使う。システム設定による実際の表示・音の可否は別に検証する。

## ファイル・データベースを保存する

UserDefaults以外を使うFeatureは、`MiniAppFiles`から専用の保存先を得られる。

```swift
let files = try MiniAppFiles.shared(context: context)
try files.write(encodedData, named: "state.json")
let data = try files.read(named: "state.json")

// SQLite等はFeatureが選んだライブラリで開く。
try files.prepareDirectory()
let databaseURL = try files.fileURL(named: "store.sqlite")
```

App Groupは既存のSideStore識別子解決を使い、取得できなければエラーにする。別の場所へ黙って保存しない。単独版やテストでは`MiniAppFiles(context:containerURL:)`へ呼出側が所有するコンテナを渡せる。保存先はコンテナ内の`Library/Application Support/JibunKit/Features/<storageNamespace>`。URLを永続保存せず、起動ごとに解決する。

ファイル名は単一成分で指定する。空文字・`.`・`..`・区切り文字・制御文字は拒否する。サブディレクトリやデータベースの管理は、公開した`directoryURL`を起点にFeature側が実装できる。これは協調するFeature間の保存先整理であり、任意のSwiftコードやシンボリックリンクを隔離するセキュリティ境界ではない。

`write`はDataを一つのファイルとしてatomicに置き換える。複数ファイルのtransaction、読取り→計算→書込みの排他、DBファイルの安全なバックアップを代行しない。同一プロセスの短い同期更新なら`MiniAppStorage.withExclusiveAccess`を使える。別プロセスからの更新は、利用するDBやファイル調整方式で扱う。`read`は未作成も含めてエラーを返し、不正なデータを空データに変換しない。

既存UserDefaultsのキーと値は自動移行しない。保存形式・schema移行・バックアップ方針はFeatureが所有する。このAPIは秘密情報用の保存庫でもない。

App Groupのコンテナは[Appleの公式API](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:))で取得する。端末での署名・App Groupアクセスの確認はCIの一時ディレクトリによるテストと区別する。

## アプリ単位のバックアップ形式（実装中）

`MiniAppBackup`は、Feature ID・schema version・任意のDataを共通JSONへ包む。`decode`は外側の形式と全entryを検証し、`selecting`は明示したIDのentryだけ返す。対象のFeatureがpayloadを検証・移行してから保存状態へ適用する。Feature固有の形式には`MiniAppBackupEntry.decodePayload`によるCodable JSON読込みも選べる。

Featureは任意の`MiniAppBackupProvider`を定義の`backup:`へ登録できる。exportはそのFeatureの整合したsnapshotを返し、prepareはpayloadを検証・移行してから適用closureを返す。prepareでは保存値を変更しない。ホストは全選択のprepareを終えてから適用する。適用中の失敗は完了済みと失敗対象を区別し、Feature間のrollbackを保証しない。CounterとReminderが実装例で、一覧のバックアップ操作から書出し・読込み・復元対象選択・上書き確認へ進む画面を実装している。Filesからの再読込み以降のUI検証はSimulatorのURL受渡し障害で未完了である。[作業記録](verification/2026-09-07-selective-backup.md)に継続タスクと境界を記載する。
