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

1. Featureのライブラリtargetへ保存・更新処理とpublicなRoot Viewを置き、Packageのlibrary productとホストの依存を追加する。ID・表示名・アイコン・Root ViewをまとめるMiniAppDefinitionはIntegration側に置く。FeatureはCore非依存でもよく、必要なら接続層から保存先や依存を注入する。Coreの共有UserDefaultsを使う場合はMiniAppStorage.sharedDefaultsで解決し、保存キーはContextから取る。独立版の@mainは別のApp targetへ残す。
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
- 不正payloadや未登録の入口IDは一覧へ戻す。詳細destinationをIntegrationが拒否した場合は現在の画面を維持する。別ミニアプリや詳細を推測しない。
- `UNTimeIntervalNotificationTrigger`の時刻は予約条件であり、正確な表示時刻を保証するものとして説明しない。

リマインダーの`ReminderNotificationScheduler`はFeature側にあり、Root Viewから渡されたContextのrequest IDとpayloadを使う。画面の「10秒後に通知」からだけ許可を要求する。foregroundでも通知を表示し、通知タップは同じdestination mappingでリマインダー画面を開く。

## WidgetやApp Intentを追加する場合

通常画面の追加だけなら、Widget extensionやApp Intentの宣言は不要である。

Widgetを追加する場合は、別extension target、Widget bundleへの登録、extensionの`Info.plist`、本体と同じApp Group entitlement、IPAへの組込み検査が追加で必要になる。共有値はfeatureの同じStoreを通して読む。Registryから生成されないため、Featureが所有する安定IDから同じContextを生成したshared Storeを使う。現在のカウンターWidgetが実例である。

App Intentを追加する場合は、Intent型と`AppShortcutsProvider`へのphrase登録に加え、Xcodeが生成するApp IntentsメタデータをIPAへ含める必要がある。Tuistのapp target内で宣言してXcodeに生成させ、Shortcuts実機確認用IPAはGitHub ActionsのmacOS／Xcode 26.6経路で生成する。現在の`AddCounterValueIntent`と`JibunKitShortcuts`が実例である。Intentからも同じshared Storeを使う。

## 検証

変更後は次を分けて確認する。

1. macOS／Linux／WSLの`swift test`またはActionsでFeature処理、ID衝突、独立保存を確認する。UserNotificationsなどApple frameworkを使う条件付きテストはmacOSで確認する。
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

## アプリ単位のバックアップと復元

`MiniAppBackup`は、Feature ID・schema version・任意のDataを共通JSONへ包む。`decode`は外側の形式と全entryを検証し、`selecting`は明示したIDのentryだけ返す。対象のFeatureがpayloadを検証・移行してから保存状態へ適用する。Feature固有の形式には`MiniAppBackupEntry.decodePayload`によるCodable JSON読込みも選べる。

Featureは任意の`MiniAppBackupProvider`を定義の`backup:`へ登録できる。exportはそのFeatureの整合したsnapshotを返し、prepareはpayloadを検証・移行してから適用closureを返す。prepareでは保存値を変更しない。ホストは全選択のprepareを終えてから適用する。適用中の失敗は完了済みと失敗対象を区別し、Feature間のrollbackを保証しない。CounterとReminderが実装例で、一覧のバックアップ操作から書出し・読込み・復元対象選択・上書き確認へ進む画面を実装している。CIでFilesの書出し・再読込みから選択復元、キャンセル、再起動後の値維持まで成功した。過去にはSimulatorのURL受渡し障害が発生しており、継続して往復テストを実行する。[作業記録](verification/2026-09-07-selective-backup.md)に継続タスクと境界を記載する。

## Widget・外部URLから開く

`MiniAppLink.url(for: id)`で`jibunkit://mini-app/<Feature ID>`を生成できる。ホストは登録済みFeatureの入口へ遷移し、起動中ならホストの遷移先を置き換える。Counter Widgetが使用例。Widget targetにも`JibunKitCore`を依存として追加する。

URLは画面を開く用途のみで、保存値の変更・復元・任意処理は実行しない。未知のID、不正なID、未対応のpath・query・fragmentは無視し現在の画面を保つ。詳細画面には`MiniAppLink.url(for: id, destination: recordID)`を使う。ホストは`MiniAppDefinition.appendDestination`へ文字列を渡し、Integrationが型・形式を検証してFeature所有のnavigation valueをpathへ追加する。拒否時はfalseを返す。RecordsのUUID接続が実例であり、ホストへFeature別switchを追加しない。表示中のsheetを強制終了しないため、sheetがあるときは閉じた後に遷移先が見える。独立版ではそのApp ShellがURL登録・受信を担う。

[AppleのWidget連携](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)に従い、Widgetの`widgetURL`とホストの`onOpenURL`を接続している。カスタムschemeは認証境界ではなく、同じschemeを登録する別アプリとの競合はOSの扱いに依存する。

## Feature内に複数の通知を持つ

`context.notificationRequestIdentifier(for: recordID)`はFeatureが管理する安定したキーから通知IDを生成する。同じキーで再予約すれば同じIDになり、異なるキーは別IDになる。キーには文字列化したレコードIDなどを使い、更新のたびにランダムIDを作らない。日時変更だけならキーを維持する。空文字列・日本語なども区別して扱う。

通知整理では`context.ownsNotificationRequestIdentifier(request.identifier)`に一致するものだけを選び、そのIDを`removePendingNotificationRequests(withIdentifiers:)`へ渡せる。配信済み通知も同様にそのrequestのidentifierで選別できる。従来の引数なし`notificationRequestIdentifier`も自身のものとして判定し、既存予約のIDは変更しない。全アプリ分を削除するAPIは使わない。

これは命名と所属判定のAPIであり、予約時刻・重複排除・再予約・通知権限の判断はFeatureが担う。予約可能な件数などOSの制約を解消するものではない。個々の通知には既存の`context.notificationUserInfo`を付けるとFeature入口へ遷移できる。レコード詳細への遷移はまだ共通化していない。

### バックアップ接続の実装箇所

Counterの接続は`Sources/CounterIntegration/CounterMiniApp.swift`の`backup:`を参照する。実際のsnapshot生成・検証・適用は`Sources/CounterFeature/CounterFeature.swift`の`backupProvider`と`restoreBackup`にある。ホストにFeature名の分岐を増やす必要はない。独立版でJibunKitCoreへの依存を避けたいFeatureでは、providerをIntegration側で作り、Featureの公開snapshot・検証・適用APIへ接続する。

データ形式を更新する際は、prepareで対応するschemaを選び、旧payloadを新しい状態へ変換し、必須値や参照整合性を検証してから`MiniAppPreparedRestore`へ渡す。この時点では保存先や通知を変更しない。実際の適用は利用者が上書きを確定した後に行われる。実行失敗で途中状態を残せないFeatureは、自身の保存方式に応じてtransactionや置換処理を使う。共通基盤による全Featureのrollbackはない。

新しいproviderの検証では、snapshotの往復だけでなく、不正payload・未知schemaをprepareで拒否して値を維持すること、片方の復元で他Featureを変更しないこと、実行時の失敗を成功として返さないことを確認する。既存の`Tests/MiniAppIntegrationTests/MiniAppBackupIntegrationTests.swift`がテストの参照先になる。

### 独立版のUIテスト

雛形は`UITests/LaunchTests.swift`とExample用UIテストtargetも生成する。生成したExample schemeで`xcodebuild test -workspace Modules/Notes/NotesExample.xcworkspace -scheme NotesExample -destination 'platform=iOS Simulator,name=<利用可能なiPhone名>'`を実行できる。最初のテストはFeatureの初期画面を確認する。実装を育てたら、利用可能になったことを示す画面要素や重要な操作へテストを更新する。

これはJibunKitのRegistryやCoreに依存しない単独版の起動確認である。ホストへ組み込んだ後の共存検証とは別に行う。既存Moduleは自動更新しないため、テストtargetが必要なら生成されるProjectとUITestsを参考に追加する。CIのSimulator検証では、その場で生成したNotesExampleを起動して同じテストを実行する。

### 詳細通知と添付を持つ参照実装

[Records](../Modules/Records/README.md)はCore非依存のFeatureへ保存先と通知操作を注入する例である。詳細通知は`context.notificationUserInfo(destination: recordID)`でURLと同じdestinationを渡せる。従来の`notificationUserInfo`は引き続き入口を開く。詳細URLのホスト遷移と通知requestの内容はCIで検証済みだが、通知センターからの詳細タップは検証中である。[証拠と未確認事項](verification/2026-09-09-detail-routing.md)を参照。

添付を含むFeatureは`MiniAppFileBackupProvider`を`fileBackup:`へ登録できる。exportは整合したsnapshot directoryとschema versionを渡し、prepareはデータを変更せず検証し、applyが復元する。ファイルproviderを含む選択はZIP、従来のData providerだけの選択はJSONとして書き出す。DBのsnapshot、schema移行、OS通知など保存先外の状態との整合はFeatureのIntegrationが所有する。Recordsは復元成功後に自身の既存通知を取り消し、復元失敗時は通知も維持する。

## ホスト状態と非同期処理の所有者

IntegrationはMiniAppDefinitionの`onHostPhaseChange:`にハンドラを登録できる。ホスト全体のactive/inactive/backgroundを、Feature画面が未生成でも受信する。Feature画面の表示/終了とは別のイベントであり、非表示になっただけで一律に停止しない。ハンドラは短くし、同期の重い処理を実行しない。

`MiniAppTaskScope`はFeature runtimeごとに別instanceを所有する。`start`へそのFeatureの非同期処理を渡し、`cancelAll`はそのscopeの処理だけへ取消要求を送る。所有者を解放しても取消を要求する。取消後の新しいstartは可能。返されたTaskのvalueを待つことで完了を観測できる。エラー報告はoperation側で行う。

Swiftの取消は協調的であり、cancelAllが返っても処理完了や資源解放は保証しない。処理側で取消を確認し、所有する資源を解放する。別Featureと共有する資源の排他・引継ぎ、background実行権限、勝手に生成されたTaskの追跡はこのscopeに含まない。Core非依存Featureには、Integrationから必要な操作やruntimeを注入できる。

Taskのoperationがscopeを所有するruntime自身を強参照し続けると、runtime解放を契機とする取消は起きない。終了操作では明示的にcancelAllし、operationへ必要な依存だけを渡すか弱参照を使う。scopeは自身のTaskから弱参照されるが、呼出側が作る保持循環まで解消しない。取消で終了する処理はTaskのvalueで完了を待ち、共有資源の引継ぎ前に所有者自身の解放を確認する。

複数Taskの終了確認にはruntime側から`await scope.cancelAllAndWait()`を使える。対象は呼出時点のTask群であり、待機中の新規startは対象外。終了中に新規処理を受けるかはruntimeが決める。scope内のoperationから呼ぶと自分自身の完了待ちになるため、外側の調停処理から呼ぶ。取消に応じないoperationがある場合は完了しない。

## 通知操作の所有者配送（開発中）

IntegrationはonNotificationActionへasyncハンドラを任意登録できる。open/dismiss/custom(action ID)、request ID、destination、文字入力を受け取る。通常openだけが既存の画面遷移を行い、dismiss/customではホストが勝手に画面を切り替えない。未登録ownerやハンドラなしの操作を他Featureへ転送しない。ハンドラ完了後にOSへ完了を返すため、長時間処理や終了しない処理を置かない。category/action宣言の合成とOS経由の独自action実証は未完。userInfo全体を渡すAPIではない。

通知categoryは`context.notificationCategoryIdentifier(for:)`でIDを生成し、ネイティブUNNotificationCategoryをMiniAppDefinition.notificationCategoriesへ登録する。通知content.categoryIdentifierにも同じIDを設定する。ホストが起動時に全Featureの和集合を一度登録する。FeatureからsetNotificationCategoriesを直接呼ぶと他Featureの登録を上書きするため、この接続を使う。カテゴリIDの重複・他ownerのIDは構成エラーとして登録前に拒否する。action IDはカテゴリ内のFeature所有値のまま保持し、文字入力actionやoptionsを独自形式へ変換しない。動的category更新の調停は未対応。

`await context.removeAllOwnedNotifications()`は、そのFeatureのnamespaceに属する予約中・配信済み通知のみを取り消す。従来の単一request IDも対象。他Featureや名前空間外の通知は保持する。取得したID一覧に対する操作なので、新規予約との原子的な停止は保証しない。復元・削除時に新規予約を止める必要がある場合はFeature runtimeで受付を調停する。Records復元後の取消が使用例。
