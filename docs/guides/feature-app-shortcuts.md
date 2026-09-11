# Featureが所有するApp Shortcut定義

状態: 単独/統合のnative metadata比較と寄与削除をCI 34550748042で検証済み。通常Counterの定義元をFeature側へ移す接続は[互換性検証](../verification/2026-09-11-host-shortcut-composition.md)をCI 34553604092で完了した。

App Intent本体はSwift Package内に置き、標準の[AppIntentsPackage接続](package-app-intents.md)で利用する。一方、今回のXcodeではPackage Providerだけの組込みでappのShortcut metadataが空になり、配列転送やcomputed property参照も抽出に拒否された。[比較証拠](../verification/2026-09-11-package-shortcut-providers.md)。この差分には、Feature所有のSwift式を生成時に一つの標準Providerへ配置する方法を用意する。

Feature内の`AppShortcuts.swift.fragment`に、通常の`AppShortcutsBuilder`へ書くSwiftの式を置く。

```swift
AppShortcut(intent: MyFeature.AddItemIntent(),
            phrases: ["Add an item in \(.applicationName)"],
            shortTitle: "Add item", systemImageName: "plus")
```

TuistのProject.swiftから、対象appに含める定義だけを列挙する。

```swift
import ProjectDescriptionHelpers

try FeatureAppShortcuts.writeProvider([
    FeatureAppShortcuts(owner: "my-feature", imports: ["MyFeature"],
        sourceFile: "Features/MyFeature/AppShortcuts.swift.fragment"),
], to: "Generated/MyAppShortcuts.swift")
```

生成ファイルをapp targetのsourcesへ追加する。通常のPackage依存とAppIntentsPackageの登録も必要。一つのappにはこの生成Providerか手書きProviderのどちらかを置く。既存の手書きShortcutを併用したい場合はその定義もfragmentへ移し、一つの生成Providerへ含める。生成物を手で編集せず、単独appと統合hostで同じFeature側のファイルを参照する。

通常hostの例はProject.swiftと`Sources/CounterIntegration/AppShortcuts.swift.fragment`。Counterの既存Intent型は公開済みの識別子を保つためapp moduleに残すが、Shortcutの文言と組立てはFeature側のfragmentが所有する。Package target内にfragmentを置く場合は、そのtargetの`exclude`へ追加する。

これはSwiftを解析する独自DSLではない。phrase、引数、availability等の式は変更せずに配置し、妥当性やOS条件はSwiftコンパイラとAppleのmetadata抽出で検証する。モジュール名を含む型名で他Featureと区別できる。`#sourceLocation`で定義元の行を診断へ残す。fragment内にimportやProvider宣言を重ねず、必要なimportは引数に指定する。

同じownerの二重登録・空のowner・空ファイル・読めないファイルは生成前に拒否する。全入力を読み終わってから一つの出力を置換するため、読み取り失敗時に以前の生成物を部分的に上書きしない。登録を外して再生成すればそのShortcut式も消え、空の登録ならProvider宣言を出さない。出力先は専用の生成ファイルを指定する。

OSのShortcut表示・Siri実行・app全体の枠や並び順などは、このソース組込みだけで解決したとは扱わない。metadata比較と実行検証を分ける。補助処理は本体のIntent識別子や実装、保存先、Runtimeを変更しない。
