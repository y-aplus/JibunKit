# v0.1時点のミニアプリ組み込み簡素化

更新日: 2026-09-04

**状態: レビュー用設計案。`codex/simplify-mini-app-integration`上の`c0b5847`は、この設計案に対する候補実装として存在する。外部エージェントは実装をやり直すのではなく、差分を本書へ照合し、不足または過剰な変更だけを直す。**

## 1. 利用者が得る結果

Swift FeatureをJibunKitへ追加するとき、基盤内部のID定義、一覧、画面遷移を個別に書き換えず、Featureのビルド宣言と1件の登録で一覧から起動できる。

## 2. 判断

**Rethink:** 従来の追加手順は、1つのミニアプリ情報を複数fileへ分散させ、利用者へJibunKit内部のswitch編集を要求していた。ID、表示情報、遷移先を1件のDescriptorへ統合し、保存と通知に必要な名前空間をContextとして渡す。

この変更は、公開済み0.1.0を捨てる再設計ではない。現在のcompile-time登録、Swift Package構成、保存形式、通知経路を維持したまま、追加時の交差箇所を減らす。

## 3. 対象範囲

本書が扱うのは、JibunKitがSwift Featureを受け取る境界である。

- ミニアプリID、表示名、SF Symbol名、Root View生成処理の一元登録。
- 一覧表示と画面遷移を同じ登録情報から生成。
- Featureへ保存キーと通知情報を渡すContext。
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
- 使用例のないStorage、Networking、Permissionなどの共通service。

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
2. 必要なら、Featureを表示可能にする薄いRoot ViewまたはAdapterを追加する。
3. `MiniAppRegistry.swift`へDescriptorを1件追加する。
4. Feature固有処理と、既存Featureとの保存・ID衝突を検証する。

通常追加では、次の基盤fileを編集しない。

- `Sources/JibunKitCore/MiniAppID.swift`
- `Sources/JibunKit/MiniAppListScreen.swift`
- `Sources/JibunKit/AppNavigation.swift`
- `Sources/JibunKit/NotificationAppDelegate.swift`

Widget、App Intent、通知、URLなどを新たに使うFeatureには、そのsystem surface固有の宣言と検証を追加してよい。それらを通常画面の追加と同じ変更量に見せない。

## 7. 設計

```text
Featureが所有する安定ID
          │
          ▼
MiniAppDescriptor ──► 一覧の表示名・アイコン
          │
          ├────────► Root View生成
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

IDから生成する値は従来どおりとする。

```text
storage namespace: <id>
storage key:       <id>.<key>
notification ID:   jibunkit.<id>.notification
```

既存値は必ず維持する。

```text
counter.value
reminder.message
jibunkit.reminder.notification
```

### 7.2 MiniAppContext

`MiniAppContext`はDescriptorのIDから生成し、Root ViewまたはAdapterへ渡す。

提供する情報は、現在必要な次の3点に限定する。

- `storageKey(_:)`
- `notificationRequestIdentifier`
- `notificationUserInfo`

汎用service containerにはしない。新しい共通機能は、複数の実例で同じ問題が確認されてから追加する。

### 7.3 MiniAppDescriptor

Descriptorは次を1件にまとめる。

- `id`
- `title`
- `systemImage`
- `MiniAppContext`を受け取るRoot View生成closure

登録例:

```swift
MiniAppDescriptor(
    id: InventoryFeature.miniAppID,
    title: "在庫管理",
    systemImage: "shippingbox"
) { context in
    InventoryRootView(context: context)
}
```

型の異なるSwiftUI Viewを同じ配列へ格納するため、型消去はRegistry境界だけで行う。Feature内部へ`AnyView`を広げない。

### 7.4 MiniAppRegistry

`MiniAppRegistry.all`を登録の唯一のsource of truthとする。

- 一覧は`all`から生成する。
- navigation destinationはIDからDescriptorを検索して生成する。
- 通知遷移は`all`から生成した登録済みID集合で検証する。
- 不正IDはDescriptorまたはContext生成時に停止させる。
- 重複IDはRegistry生成時に停止させる。

### 7.5 Navigationと通知

`AppNavigation`は登録済みIDだけをpathへ設定する。未登録IDまたは解決不能な通知payloadではpathを空にし、ミニアプリ一覧へ戻す。別のミニアプリを推測して開かない。

通知centerのdelegateはホストに1つだけ置く。FeatureごとのAppDelegateを追加しない。

## 8. fileごとの責務

| file | 責務 |
| --- | --- |
| `Sources/JibunKitCore/MiniAppID.swift` | 開いたID型、ID検証、Context、通知payload解決 |
| `Sources/<Name>Feature` | Feature固有ID、処理、保存形式 |
| `Sources/JibunKit/MiniAppRegistry.swift` | Descriptor定義と全Featureの登録 |
| `Sources/JibunKit/MiniAppListScreen.swift` | Registryから一覧とdestinationを生成 |
| `Sources/JibunKit/AppNavigation.swift` | 登録済みIDだけを開く |
| `Sources/JibunKit/NotificationAppDelegate.swift` | 通知payloadを登録済みIDへ解決してnavigationへ渡す |
| `Package.swift` | Feature targetと依存の明示 |

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
- ID、表示名、アイコン、destinationが1件のDescriptorにまとまっている。
- 各Featureが自身のIDを所有する。
- Registryが不正IDと重複IDを受け入れない。

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

- 一覧にカウンターとリマインダーが表示され、両方を開ける。
- `counter.value`と`reminder.message`が更新前から維持される。
- Counterの画面、App Shortcut、Widgetが同じ値を扱う。
- リマインダー通知を予約でき、foregroundと終了状態の通知タップからリマインダーを開ける。
- SideStoreの署名更新後も同じ項目を確認できる。

ビルド成功だけで実機合格としない。

## 11. 候補実装の状態

`codex/simplify-mini-app-integration`には次のlocal commitがある。

- `c0b5847 refactor: simplify mini-app registration`
- `e20c9ae docs: clarify standalone app feature goal`

`c0b5847`では、2026-09-04にWSLの全15テスト、`xtool dev build --ipa`、IPAのZIP検査が成功した。実機検証は未実施である。

外部エージェントは、最初に次を行う。

1. `AGENTS.md`と本書を最後まで読む。
2. `git status --short`、現在branch、上記2 commitを確認する。
3. `c0b5847`の実装を本書の受入条件へ照合する。
4. 過剰な抽象化や本書の対象外機能を追加しない。
5. 不足修正がある場合だけ変更し、自動検証を再実行する。
6. 独立した作業単位ごとに、その変更だけをlocal commitへまとめる。

新しいbranchを無断で作らない。checkpointごとにはpushしない。remote検証が必要な節目では、リポジトリの`AGENTS.md`とユーザーの指示に従う。

## 12. 未完了と次の判断

本書の自動検証は候補実装で合格済みだが、利用者向け更新としての実機検証は未完了である。外部エージェントへ依頼する作業は、コードレビュー、自動検証の再現、不足修正のいずれかを明示する。Feature化支援や特定アプリの移植を、この依頼へ暗黙に追加しない。
