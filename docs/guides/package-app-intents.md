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

自動提示するApp Shortcutは、現在検証済みの経路ではhostの一つの`AppShortcutsProvider`からpackageのIntentを参照する。任意のIntentすべてをApp Shortcutへ登録する必要はない。複数Packageが各自のProviderを所有する構成は、別途検証中であり、OS不可能とは判定していない。

二Packageの単独/統合appで、Xcodeが生成した識別子・型名・引数・戻り値・実行modeの一致と、iOS上の`perform()`から他Featureを変更しないことを検証した。[native fixtureと証拠](../verification/2026-09-11-package-app-intents.md)を参照。OS Shortcuts/Siriからの起動、AppEntity query、同名型衝突、Widget/Controlへの接続はこの証拠に含めない。

Intentの型名は他Featureと区別できる名前にする。既に利用中のIntentを移動・改名するときは、保存済みShortcutとの互換性を別途確認する。既存Counter intentは今回移動しておらず、元の識別子を維持している。

Apple標準の契約: [AppIntentsPackage](https://developer.apple.com/documentation/appintents/appintentspackage)、[App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)。
