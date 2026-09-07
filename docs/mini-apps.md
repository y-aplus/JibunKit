# ミニアプリの追加

JibunKitのミニアプリは、ビルド時にSwift Packageへ組み込む。組み込み単位は`@main`を持つ独立アプリtargetではなく、SwiftライブラリtargetとしてコンパイルできるFeatureである。動的プラグイン、任意のIPA読込み、ミニアプリストアは対象ではない。

リマインダーが、保存・画面・通知を持つ最小の実例である。ID、表示名、アイコン、遷移先はFeature側の1件の定義へまとめ、ホストの一覧や画面遷移へ個別のswitchを増やさない。

## 通常の画面を追加する

1. `Sources/<Name>Feature`へ保存・更新処理、`MiniAppContext`を受け取るpublicなRoot View、ID・表示名・アイコン・Root Viewをまとめたpublicな定義を置き、`Package.swift`へライブラリtargetと本体からの依存を追加する。StoreのUserDefaults解決は`MiniAppStorage.sharedDefaults`を使い、保存キーはContextから取る。独立版も維持する場合、独立版の`@main`は別のapp targetへ残し、Feature targetへ含めない。既存コードとの変換が必要な場合は、Feature側に薄いAdapterを置き、そのRoot Viewから呼ぶ。
2. `Sources/JibunKit/MiniAppRegistry.swift`の`all`へ定義を1件列挙する。ID・表示名・アイコン・destinationをRegistry側に書かない。IDは小文字英字で始め、小文字英数字、`.`、`-`、`_`だけを使う。IDは保存namespace、通知request ID、通知payloadの遷移先になるため、公開後に安易に変更しない。
3. `MiniAppValidator.validate(ids:)`をテストから呼び、ID・保存namespace・通知request IDの不正と衝突を事前確認する。Storeの保存キーはstatic定数ではなくContextから初期化したinstance値にし、通知予約のrequest IDとpayloadもContextから取る。別ミニアプリのStoreやキーへ依存させない。
4. `JibunKitCoreTests`でID、保存namespace、通知request IDを、統合テストで同じUserDefaults suite内の保存値が互いを変えないことを確認する。

最小構成の例:

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

App Intentを追加する場合は、Intent型と`AppShortcutsProvider`へのphrase登録に加え、Xcodeが生成するApp IntentsメタデータをIPAへ含める必要がある。現在のxtool 1.17.0ローカル経路ではこのメタデータを生成できないため、Shortcuts実機確認用IPAはGitHub ActionsのmacOS／Xcode 26.6経路で生成する。現在の`AddCounterValueIntent`と`JibunKitShortcuts`が実例である。Intentからも同じshared Storeを使う。

## 検証

変更後は次を分けて確認する。

1. WSLの`swift test`でfeature処理、ID衝突、独立保存を確認する。
2. `xtool dev build --ipa`でiOSフレームワークを含むコンパイル、Widget組込み、IPAのZIP整合性を確認する。
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
