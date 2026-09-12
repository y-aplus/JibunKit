> 履歴・設計経緯: この日付の設計/検討を保持した資料です。現在の実装状況は[公開版とmainの状態](../../status.md)と[統合差分台帳](../../coexistence-ledger.md)、上位基準は[共存の完成基準](../../coexistence-boundaries.md)を参照してください。

# v0.1時点のミニアプリ組み込み簡素化

更新日: 2026-09-04

**状態: 共通基盤を実装済み。2026-09-07にZaikoをmainへの統合対象から外し、カウンターとリマインダーで再検証する。試験移植は元の作業ブランチとローカルのignore対象に保存する。**

## 1. 利用者が得る結果

Swift FeatureをJibunKitへ追加するとき、基盤内部のID定義、画面、一覧、画面遷移を個別に書き換えず、Featureのビルド宣言と1件の登録で一覧から起動できる。

## 2. 判断

**Rethink:** 従来の追加手順は、1つのミニアプリ情報を複数fileへ分散させ、利用者へJibunKit内部のswitch編集を要求していた。ID、表示情報、遷移先を1件のDefinitionへ統合し、保存と通知に必要な名前空間をContextとして渡す。

この変更は、公開済み0.1.0を捨てる再設計ではない。現在のcompile-time登録、Swift Package構成、保存形式、通知経路を維持したまま、追加時の交差箇所を減らす。

## 3. 対象範囲

本書が扱うのは、JibunKitがSwift Featureを受け取る境界である。

- ミニアプリID、表示名、SF Symbol名、Root View生成処理の一元登録。
- 一覧表示と画面遷移を同じ登録情報から生成。
- Featureへ保存キーと通知情報を渡すContext。
- CounterとReminderのRoot ViewをFeature側へ移し、Contextを使う基準実装にする。
- Reminderの通知予約処理をFeature側へ移し、Contextのrequest IDとpayloadを使う。
- 不正または重複したIDの検出。
- 未登録の通知遷移先を開かない安全なfallback。
- カウンターとリマインダーの既存保存値、通知、Widget、App Intentの維持。
- ミニアプリ追加手順と基盤更新手順の更新。

## 4. 対象外

次は本書の実装対象に含めない。

- standalone Swift／SwiftUIアプリをFeatureライブラリと薄いAdapterへ分離する支援。この支援は1.0の目標候補として維持する。
- 特定の既存アプリの組み込み。
- source解析、コード変換、雛形生成、Package.swiftの自動編集。
- 動的plugin、ミニアプリストア、ビルド不要の追加。
- Info.plist、entitlements、Widget、App Intent、URL schemeの自動統合。
- 本設計時点で具体化していないStorage、Networking、Permissionなどの追加service。これは将来の先行実装を禁止する意味ではない。

## 5. 変更前の負担

通常のミニアプリ追加でも、利用者は次を別々に編集する必要があった。

1. `Package.swift`へFeature targetと依存を追加する。
2. `MiniAppID.swift`の閉じたenumへcaseを追加する。
3. SwiftUI画面を追加する。
4. `MiniAppListScreen.swift`の表示名、アイコン、destinationのswitchをすべて更新する。
5. ID、保存namespace、通知IDの衝突テストを更新する。

同じ情報が複数箇所へ分散し、公開基盤の更新を取り込む際も`MiniAppID.swift`と`MiniAppListScreen.swift`が競合点になっていた。

## 6. 変更後の追加手順

通常の画面を持つFeatureの追加手順は次のとおりとする。

1. FeatureライブラリtargetとJibunKitからの依存を`Package.swift`へ追加する。
2. Feature targetから`MiniAppContext`を受け取るpublicなRoot Viewを公開する。既存コードとの変換が必要な場合は、Feature側に薄いAdapterを置き、そのRoot Viewから呼ぶ。
3. `MiniAppRegistry.swift`の`all`へFeatureの定義を1件列挙する。
4. Feature固有処理と、既存Featureとの保存・ID衝突を検証する。

通常追加では、次の基盤fileを編集しない。

- `Sources/JibunKitCore/MiniAppID.swift`
- `Sources/JibunKit/MiniAppListScreen.swift`
- `Sources/JibunKit/AppNavigation.swift`
- `Sources/JibunKit/NotificationAppDelegate.swift`

ミニアプリ固有の画面や通知予約処理を`Sources/JibunKit`へ追加しない。JibunKit targetは、Registry、navigation、通知応答などホスト全体の処理だけを持つ。

Widget、App Intent、通知、URLなどを新たに使うFeatureには、そのsystem surface固有の宣言と検証を追加してよい。それらを通常画面の追加と同じ変更量に見せない。

## 7. 設計

```text
Featureが所有する安定ID
          │
          ▼
MiniAppDefinition ──► 一覧の表示名・アイコン
          │
          ├────────► Feature Root View生成
          │
          ├────────► 登録済みID集合 ──► 通知遷移の検証
          │
          ▼
 MiniAppContext ────► 保存namespace・通知ID・通知payload
```

### 7.1 MiniAppID

`MiniAppID`は閉じたenumではなく、文字列を保持する`Hashable`かつ`Sendable`な値型とする。Featureは自身の安定IDを所有する。新しいFeatureを追加するために`JibunKitCore`を変更しない。

IDは次を満たす。

- 小文字英字で始まる。
- 使用可能文字は小文字英字、数字、`.`、`-`、`_`。
- Registry内で一意である。
- 公開後は、保存データと外部経路の移行なしに変更しない。

ID中の`.`を`%2E`へ変換したnamespaceを使う。`%`はIDに許可しないため、区切り文字との混同や他Featureのキー・通知prefixとの衝突がない。ドットのない既存IDは従来どおりとする。

```text
storage namespace: <idのドットを%2Eに変換>
storage key:       <namespace>.<key>
notification ID:   jibunkit.<namespace>.notification
```

既存値は必ず維持する。

```text
counter.value
reminder.message
jibunkit.reminder.notification
```

### 7.2 MiniAppContext

`MiniAppContext`は定義のIDから生成し、FeatureのRoot ViewまたはAdapterへ渡す。受け取ったFeatureは、保存キーと通知情報を同じContextから取得する。

提供する情報は、現在必要な次の3点に限定する。

- `storageKey(_:)`
- `notificationRequestIdentifier`
- `notificationUserInfo`

CounterとReminderもこの経路を使う。ReminderのRoot ViewはContextを通知予約処理へ渡し、通知予約処理はrequest IDとpayloadを直接`MiniAppID.reminder`から再生成しない。

CounterとReminderのRoot ViewはContextをStoreへ渡し、Storeは`storageKey(_:)`から保存キーを得る。Storeの保存キーはstatic定数ではなく、Contextから初期化したinstance値にする。

WidgetやApp IntentはRegistryから生成されないため、Featureが所有する安定IDから同じContextを生成してStoreへ渡してよい。既存のshared Storeもこのdefault Contextから構成し、`counter.value`を維持する。Contextを受け取れる画面や処理が、同じ値を別経路で再生成することは認めない。

共通機能は目指す開発体験と運用上の要求から先行設計・実装してよい。複数の実例や個別アプリの完成を着手条件にしない。2026-09-07の[設計原則](2026-08-28-jibunkit-1.0-direction.md)を優先し、基盤が保証する境界とFeature自身の責任を明確にする。

### 7.3 MiniAppDefinition

定義は次を1件にまとめる。

- `id`
- `title`
- `systemImage`
- `MiniAppContext`を受け取るRoot View生成closure

登録例:

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

CounterとReminderの登録も同じ形にする。

```swift
ReminderMiniApp.definition // id: .reminder、title: "リマインダー"
```

型の異なるSwiftUI Viewを同じ配列へ格納するため、型消去はRegistry境界だけで行う。Feature内部へ`AnyView`を広げない。

### 7.4 MiniAppRegistry

`MiniAppRegistry.all`を登録の唯一のsource of truthとする。

- 一覧は`all`から生成する。
- navigation destinationはIDから定義を検索して生成する。
- 通知遷移は`all`から生成した登録済みID集合で検証する。
- 不正IDは定義またはContext生成時に停止させる。
- 重複IDはRegistry生成時に停止させる。

### 7.5 Navigationと通知

`AppNavigation`は登録済みIDだけをpathへ設定する。未登録IDまたは解決不能な通知payloadではpathを空にし、ミニアプリ一覧へ戻す。別のミニアプリを推測して開かない。

通知centerのdelegateはホストに1つだけ置く。FeatureごとのAppDelegateを追加しない。

## 8. fileごとの責務

| file | 責務 |
| --- | --- |
| `Sources/JibunKitCore/MiniAppID.swift` | 開いたID型、ID検証、Context、通知payload解決 |
| `Sources/JibunKitCore/MiniAppDefinition.swift` | Feature所有の定義(ID・表示名・アイコン・Root View生成) |
| `Sources/JibunKitCore/MiniAppStorage.swift` | App Group解決の集約 |
| `Sources/JibunKitCore/MiniAppValidator.swift` | ID・保存namespace・通知IDの事前検査 |
| `Sources/<Name>Feature` | Feature固有ID、定義、Root ViewまたはAdapter、処理、保存形式、Feature固有の通知予約 |
| `Sources/JibunKit/MiniAppRegistry.swift` | Featureの定義の列挙 |
| `Sources/JibunKit/MiniAppListScreen.swift` | Registryから一覧とdestinationを生成 |
| `Sources/JibunKit/AppNavigation.swift` | 登録済みIDだけを開く |
| `Sources/JibunKit/NotificationAppDelegate.swift` | 通知payloadを登録済みIDへ解決してnavigationへ渡す |
| `Package.swift` | Feature targetと依存の明示 |

移行完了後、`Sources/JibunKit/CounterScreen.swift`、`Sources/JibunKit/ReminderScreen.swift`、`Sources/JibunKit/ReminderNotificationScheduler.swift`は残さない。iOS専用のViewと通知処理はFeature target内で`#if os(iOS)`により囲み、Linux上のSwift Packageテストを維持する。

## 9. 互換性と安全条件

- bundle ID、App Group、0.1.0の保存キーを変更しない。
- カウンターとリマインダーのID raw valueを変更しない。
- 通知許可をアプリ起動時に要求しない。
- 未登録・古い・不正な通知targetは一覧へ戻す。
- WidgetとApp Intentから参照するCounter処理を変更しない。
- 生成したIPA、SDK、署名材料、credential、実データをGitへ追加しない。

## 10. 受入条件

### 10.1 構造

- `MiniAppID`が`CaseIterable`な閉じたenumではない。
- `MiniAppListScreen`にFeatureごとのswitchがない。
- ID、表示名、アイコン、destinationが1件の定義にまとまっている。
- 各Featureが自身のIDを所有する。
- Counter・Reminderが、`MiniAppContext`を受け取るFeature側Root Viewを公開する。
- RegistryがContextを各FeatureのRoot Viewへ渡す。
- 各FeatureのRoot ViewがContextをStoreへ渡し、Storeが保存キーをContextから得る。
- Reminderの通知予約が、受け取ったContextのrequest IDとpayloadを使う。
- ミニアプリ固有の画面と通知予約処理が`Sources/JibunKit`に残っていない。
- Registryが不正IDと重複IDを受け入れない。
- `docs/mini-apps.md`と`docs/updating.md`が、Feature側Root ViewとContextの実利用を追加手順として説明する。

### 10.2 自動検証

WSLのリポジトリ直下で次を実行する。

```bash
swift test
xtool dev build --ipa
unzip -t xtool/JibunKit.ipa
```

合格条件:

- 全テストが成功する。
- JibunKit本体とWidgetがiOS向けにリンクされる。
- `xtool/JibunKit.ipa`が生成される。
- IPAのZIP検査にerrorがない。
- `.build`と`xtool`の生成物がGit追跡対象にならない。

### 10.3 更新用IPAの実機検証

本変更を利用者向け更新として配布する前に、既存JibunKitを削除せず上書きする。

- 一覧にカウンター・リマインダーが表示され、すべて開ける。
- `counter.value`と`reminder.message`が更新前から維持される。
- Counterの画面、App Shortcut、Widgetが同じ値を扱う。
- リマインダー通知を予約でき、foregroundと終了状態の通知タップからリマインダーを開ける。
- SideStoreの署名更新後も同じ項目を確認できる。

ビルド成功だけで実機合格としない。

## 11. 実装と検証の状態

Feature所有の定義、Root View、Context由来の保存・通知、共通保存排他、通知delegateの修正をmainへの統合対象とする。基盤の先行実装に個別アプリの完成は要求しない。

現在の検証範囲と結果は[レビュー修正の検証](../../verification/2026-09-07-review-fixes.md)へ記録する。今回の統合はリリース公開を含まない。
