# Swift PackageにApp Intentsを置く

FeatureのIntent実装はapp targetへ移動せず、Swift Packageの公開型として置ける。標準`AppIntentsPackage`をpackage側とhost側で宣言して接続する。JibunKit独自のメタデータ生成やIntent wrapperは不要。

```swift
// FeatureのSwift Package内
import AppIntents
public struct NotesIntentPackage: AppIntentsPackage {}
public struct NotesAddIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add note"
    @Parameter(title: "Text") public var text: String
    public init() {}
    public func perform() async throws -> some IntentResult {
        // Feature自身のservice/storeへ接続する。
        return .result()
    }
}
```

これは接続形だけの例であり、保存処理は省略している。実際のIntentでも通常画面と同じFeature所有の保存・寿命・復元調停を使う。

```swift
// Sources/JibunKit等のapp target内
import AppIntents
import NotesFeature
struct JibunKitIntentPackages: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [NotesIntentPackage.self]
    }
}
```

`Project.swift`のapp targetにFeatureのpackage product dependencyも登録する。単独appや別extensionでも、各targetのpackage dependencyと`includedPackages`へ必要なものだけを登録する。RuntimeのMiniAppDefinition登録とは別のビルド時接続である。

自動提示するApp Shortcutは、現在検証済みの経路ではhostの一つの`AppShortcutsProvider`からpackageのIntentを参照する。任意のIntentすべてをApp Shortcutへ登録する必要はない。FeatureがShortcut式を所有する場合は[ソース合成ガイド](feature-app-shortcuts.md)を使う。Package Providerの参照を転送するだけではnative抽出を通らなかったため、式を一つの標準Providerへ配置する。

二Packageの単独/統合appで、Xcodeが生成した識別子・型名・引数・戻り値・実行modeの一致と、iOS上の`perform()`から他Featureを変更しないことを検証した。[native fixtureと証拠](../verification/2026-09-11-package-app-intents.md)を参照。この初回の証拠にはOS Shortcuts/Siriからの起動、AppEntity query、同名型衝突、Widget/Controlへの接続を含めない。後続のentity/query比較は下記を参照。

Intentの永続識別子は他Featureと区別できる値にする。同名Swift型もmoduleを分け、標準persistentIdentifierを明示する方法でnative比較済み（[証拠](../verification/2026-09-11-same-named-package-intents.md)）。既に利用中のIntentを移動・改名するときは、保存済みShortcutとの互換性を別途確認する。既存Counter intentは今回移動しておらず、元の識別子を維持している。

Apple標準の契約: [AppIntentsPackage](https://developer.apple.com/documentation/appintents/appintentspackage)、[App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)。

## 同名のAppEntity/queryと永続識別子

Swift Packageを分けるだけではnative metadataの名前衝突を防げなかった。同名`Entry`と`EntryQuery`が統合時に一件ずつへ減ることを確認した。[失敗と修正の証拠](../verification/2026-09-11-package-entity-queries.md)。新規FeatureではOSへ公開する型にFeature所有の安定した識別子を定め、標準`persistentIdentifier`を明示する。entityとqueryは別々に指定する。

```swift
public struct Entry: AppEntity {
    public static let persistentIdentifier = "com.example.notes.entry"
    // 通常のid、defaultQuery、表示・propertyを定義する。
}
public struct EntryQuery: EntityStringQuery {
    public static let persistentIdentifier = "com.example.notes.entry-query"
    // 通常のID解決・検索・候補を実装する。
}
```

この例は識別子宣言の抜粋。型名とレコードIDはFeature内の名前を使える。二Packageの同名型・同じレコードIDについて、native metadataの両方の保持、検索・候補、編集後の再取得、削除時の他owner非参照をCI 34558958859で確認した。OS Shortcutsの候補UI/保存済みworkflow実行は別の検証境界である。

既存公開型の永続識別子を不用意に変更しない。改名・移動・独立appからの統合時は以前の識別子との互換性を確認する。毎回のUUID生成やhost名からの自動再生成は使わない。独自メタデータ書換えやquery転送機構は不要。

Apple標準: [PersistentlyIdentifiable](https://developer.apple.com/documentation/appintents/persistentlyidentifiable)、[persistentIdentifier](https://developer.apple.com/documentation/appintents/persistentlyidentifiable/persistentidentifier)。

## 統合で消えた定義を検出する

通常のbuild成功だけでは同名定義の衝突を検出できなかったため、意図した単独版のnative metadataと統合版を比較するツールを用意した。

```sh
python3 Tools/verify-app-intents-integration.py \
  --baseline /path/to/StandaloneA.app/Metadata.appintents/extract.actionsdata \
  --baseline /path/to/StandaloneB.app/Metadata.appintents/extract.actionsdata \
  --integrated /path/to/Combined.app/Metadata.appintents/extract.actionsdata
```

引数には統合後も残す予定の定義を持つ、Xcode生成JSONを指定する。検査はIntent/entity/queryのidentifier衝突、統合後の型の欠落・置換、entity引数・query・property参照の変化を拒否し、衝突した識別子と型名を示す。複数baselineが同じ型・参照を含む場合は重複登録として扱わず、統合版の追加定義も許容する。異なる単独appの無関係なhost専用Intentまでbaselineへ含める用途ではない。

これは明示したbaselineの保持検査であり、全依存関係の自動発見や、Shortcut文言・Siri実行・既存workflow互換性の包括検査ではない。出力metadataだけを渡して既に失われた定義を推測することもできない。既存Package比較CIはこの検査に加え、entity/query辞書全体の比較とiOS直接実行を続ける。
