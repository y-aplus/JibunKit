# 個人用 SwiftUI Super App 構想メモ

## 1. 背景

SideStore では、実用上インストールできる自作アプリ枠が厳しく、複数の小さな自作 iOS アプリを個別に持つコストが高い。

LiveContainer のような方式でアプリ数制限を回避する案もあるが、既存 IPA をホストアプリ内部で疑似実行する設計のため、以下のネイティブ機能に制約が出やすい。

- App Extension / Widget
- Remote Push Notification
- Entitlements
- App Group
- その他、アプリ単位のネイティブ権限・ライフサイクル

今回の目的は「既存 IPA を無理に複数実行すること」ではなく、**自作ツールを最初から 1 個のネイティブ iOS アプリとしてまとめること**。

---

## 2. 基本方針

1 個のホストアプリの中に複数の小機能を Feature として持たせる。

```text
PersonalHub.app
├─ Home / Launcher
├─ Shared
│  ├─ Notifications
│  ├─ Storage
│  ├─ Networking
│  ├─ Permissions
│  ├─ App Intents
│  └─ Design System
├─ Features
│  ├─ Travel
│  ├─ ToolB
│  ├─ ToolC
│  └─ ...
└─ Widgets.appex
   ├─ Travel Widget
   ├─ ToolB Widget
   └─ ...
```

iOS から見れば 1 アプリなので、SideStore の枠消費は 1 個。

### 重要な設計原則

- 新機能追加の限界コストを低くする
- 「小さすぎて単独アプリにするほどではない」ツールを気軽に追加できるようにする
- 最初から複雑な plugin loader や microfrontend を作らない
- 動的ロードより compile-time 登録を優先
- Feature ごとに巨大な Clean Architecture を強制しない
- 小さい Feature はフォルダ単位、大きくなったら Swift Package へ昇格

---

## 3. 既存の SwiftUI Super App starter 調査結果

### 結論

**「個人用 SwiftUI Super App starter」として、そのまま clone して使える成熟した定番 OSS はほぼない。**

ただし、参考になる設計やテンプレートは複数ある。

### 3.1 Microapps Architecture

Majid Jabrayilov の Microapps Architecture が思想として最も近い。

- Feature ごとに Swift module 化
- 必要なら単独アプリとして起動可能
- 大規模アプリの分割手法だが、個人 Super App では逆向きに利用できる

今回の用途では、

```text
Host
├─ TravelFeature
├─ UtilityFeature
├─ ResearchFeature
└─ Shared
```

という構造に応用する。

### 3.2 AxelkHellberg/swift-structure-template

構造はかなり近い。

```text
AppCore
AppDesignSystem
AppNavigation
AppPersistence
Features/
```

Feature 分離の参考として有用。

ただし成熟度・実績は弱いため、そのまま依存するより「設計を盗む」用途が適切。

### 3.3 nimblehq/ios-templates

企業向けとして成熟度が高い。

- SwiftUI
- SPM
- modular architecture
- DI
- CI
- lint / format
- project generation

一方で個人用途には重い。

Ruby / Tuist / Fastlane / 複数 build configuration など、Personal Super App には過剰な部分が多い。

### 3.4 ModernCleanArchitectureSwiftUI

Architecture reference として優秀。

ただし、数十〜数百行の小ツールにまで Domain / UseCase / Repository 分離を強制すると、追加コストが高すぎる。

### 3.5 SwiftfulStarterProject 等

Push Notification、Routing、Haptics など共通機能の参考にはなる。

ただし VIPER / RIBs 系は今回の「小機能を軽く追加する」方向とは相性が悪い。

---

## 4. 推奨する基盤

最初は極力薄くする。

```text
PersonalHub
├─ App
│  ├─ PersonalHubApp.swift
│  └─ HomeView.swift
├─ Core
│  ├─ NotificationService.swift
│  ├─ StorageService.swift
│  ├─ PermissionService.swift
│  └─ AppIntentService.swift
├─ DesignSystem
├─ Features
│  ├─ Travel
│  ├─ ToolB
│  └─ ToolC
└─ Widgets
```

各 Feature の登録は、動的 plugin ではなく単純な Registry で十分。

```swift
struct ToolDescriptor: Identifiable {
    let id: String
    let title: String
    let icon: String
    let destination: AnyView
}
```

または protocol ベース。

```swift
protocol ToolModule {
    static var id: String { get }
    static var title: String { get }
    static var icon: String { get }
    static func makeView() -> AnyView
}
```

### Feature 分割ルール

最初からすべて SPM package にしない。

```text
Features/
  Travel/
  Calculator/
  Timer/
```

くらいで始める。

以下の条件を満たしたら package 化を検討。

- Feature が大きくなった
- 単独テストしたい
- 他アプリでも再利用したい
- Build time 分離の効果が出る

---

## 5. TravelCancas / TabiScore iOS 版

GitHub Actions 上では、iOS 版を Swift / Xcode でビルドしている。

Workflow では以下を実施している。

- macOS runner
- `xcodebuild`
- `ios/TabiPlotIOS.xcodeproj`
- `TabiPlotIOS` scheme
- unsigned IPA 生成
- Widget extension 存在確認
- IPA artifact upload
- SideStore / AltStore 向け配布 metadata 生成
- `ios-app-dist` への release publish

iOS 版は Web 版フル機能そのものではなく、**持ち歩き用のコンパクト companion app** という位置付け。

このため、Super App 統合対象としては比較的扱いやすい可能性が高い。

---

## 6. 既存アプリをどう統合するか

### 原則

既存アプリを最初から Super App の理想構造へ全面改修しない。

まずは以下を見る。

- `@main` から RootView までの依存
- Navigation
- 状態管理
- 永続化
- Notifications
- Widget
- App Intents
- Firebase / Location / Maps 等のネイティブ依存
- Bundle ID / App Group 前提

### 望ましい移行

```text
既存アプリ
   ↓
薄い Adapter / Facade
   ↓
Super App Host
```

既存アプリがすでに

```text
App
 ↓
RootView
 ↓
Feature Views / Services
```

のように分離されているなら、RootView 以下を Feature として取り込める。

### TravelCancas を基準サンプルとして使う

TravelCancas の iOS 版は、

- Swift
- Widget あり
- 実際に SideStore 配布している
- コンパクト companion

なので、Super App 基盤を決める前に一度査定する価値が高い。

良い構造があれば基盤側へ採用し、悪い部分だけ Adapter 化する。

---

## 7. Widget / Notification / App Intents の扱い

Super App の強みは、これらを Host 側で正式に持てること。

### Widget

1 個の Widget Extension 内に複数 Widget をまとめられる。

```text
PersonalHubWidgets.appex
├─ TravelWidget
├─ TimerWidget
└─ ResearchWidget
```

### Notifications

Host 側に共通 NotificationService を持たせ、各 Feature が呼ぶ。

```swift
notificationService.schedule(...)
```

### App Intents / Shortcuts

Feature ごとに Intent を定義してもよいが、登録・ライフサイクルは Host 側に集約する。

### Entitlements

Super App 全体で必要な entitlement の和集合を持つ。

これは LiveContainer 型と大きく違う。

---

## 8. LiveContainer を fork して土台にする案

### 結論

**筋が悪い。**

LiveContainer は、

- 既存 `.app` / IPA の実行
- `dlopen`
- Guest App の起動
- 独立アプリを Host 内で疑似実行

のための特殊な runtime / loader。

一方で今回欲しいのは、

- compile-time で Feature をリンク
- 1 個の正規アプリとしてビルド
- Host が Navigation / Services / Entitlements を管理

という構造。

LiveContainer を改造してこれを実現しようとすると、核心部分を捨てることになり、最終的にはほぼ別物になる。

### LiveContainer から借りるべきもの

コードベースではなく UI / UX。

- アプリ風ランチャー
- アイコン付き一覧
- 並び替え
- Feature の有効 / 無効
- per-tool settings
- metadata
- データ管理画面

つまり、

**LiveContainer は fork 対象ではなく、製品 UI の参考。**

---

## 9. 推奨アーキテクチャの最終像

```text
PersonalHub
│
├─ App Shell
│  ├─ Home
│  ├─ Settings
│  └─ Tool Registry
│
├─ Shared Native Capabilities
│  ├─ Notifications
│  ├─ Widgets
│  ├─ App Intents
│  ├─ Storage
│  ├─ Permissions
│  └─ Networking
│
├─ Features
│  ├─ Travel
│  ├─ Utility A
│  ├─ Utility B
│  └─ ...
│
└─ Extensions
   └─ PersonalHubWidgets
```

### 設計の優先順位

1. Feature を追加しやすい
2. 既存アプリを無理なく移せる
3. Widget / Notification / App Intents が壊れない
4. 小機能の追加コストが低い
5. Architecture を作ること自体が目的にならない

---

## 10. 次に見るべきこと

TravelCancas の Swift 側を実際に読んで、以下を確認する。

1. `@main` / RootView の構造
2. Navigation
3. 状態管理
4. Firebase / Maps / Location 等のサービス依存
5. Widget とのデータ共有
6. App Group
7. Local / Remote Notification
8. Feature として切り出せる境界

その結果を見て、次のどちらかを決める。

### A. TravelCancas を母体に Super App 化

向いている条件:

- App Shell が薄い
- RootView 以下が分離されている
- Shared service が再利用しやすい
- 既存 Widget / entitlement をそのまま拡張しやすい

### B. 新規 PersonalHub を作り TravelCancas を Feature として移植

向いている条件:

- App lifecycle 依存が強い
- Travel 固有の前提が多い
- 新しい Host を作った方が境界がきれい

---

## 11. 実装方針の一言要約

**LiveContainer のような「複数アプリを無理に動かす箱」ではなく、最初から 1 個の正規 iOS アプリとして複数の小さな自作ツールを Feature 化する。**

既存アプリは全面リライトせず、TravelCancas の Swift 版を基準サンプルとして査定し、必要最小限の Adapter で統合する。

基盤は薄く保ち、Feature 追加の速さを最優先する。
