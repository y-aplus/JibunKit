# Featureのビルド設定を合成する

統合したFeatureのInfo.plist/entitlementsは、一つのnative targetの設定になる。各Featureの要求を`Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift`へ登録する。Tuist標準のProjectDescriptionHelpersとPlist.Valueを使い、追加の設定形式や製品用generatorを設けない。

```swift
import ProjectDescription

public enum EnabledFeatureBuildRequirements {
    public static let app = FeatureBuildConfiguration(features: [
        .init(owner: "camera", infoPlist: [
            "NSCameraUsageDescription": "写真を撮影します",
        ]),
        .init(owner: "scanner", infoPlist: [
            "NSCameraUsageDescription": "書類を読み取ります",
        ]),
    ], infoPlistResolutions: [
        "NSCameraUsageDescription": "カメラで写真を撮影し、スキャナーで書類を読み取ります",
    ])
    public static let widget = FeatureBuildConfiguration()
}
```

`app`と`widget`は別々に合成し、必要なtargetへだけ要求を登録する。FeatureのSwift package依存とRuntime Registryの登録も従来通り必要で、実行時のMiniAppDefinitionからビルド済みのplistを書き換えることはできない。別target/standalone appでも同じ`FeatureBuildConfiguration.compose`を使える。

## 合成規則

- hostと各Featureが同じkeyへ同じ値を指定した場合は共有する。独自key、ネストしたdictionary、数値等のTuistのplist値も指定できる。
- `UIBackgroundModes`、`BGTaskSchedulerPermittedIdentifiers`、`LSApplicationQueriesSchemes`、App Group、Keychain access group、Associated Domainsは文字列配列を重複除去・ソートして合成する。
- それ以外の異なる値は、keyと要求元を示して生成を止める。用途説明を単純連結したり、最後のFeatureで上書きしたりしない。統合担当が`infoPlistResolutions`/`entitlementResolutions`へ合意した値を明記する。
- URL Typesやdocument types等の構造化配列も、異なる要求なら明示的に合成結果を指定する。一般的なkey別schema validatorはまだ提供しない。
- 空/重複のowner、文字列集合keyの不正な型、要求のないkeyへの余ったresolutionを拒否する。bundle identifier/executableはFeatureのplistで変更せずnative targetで設定する。

独自のnative target設定を禁止するものではない。たとえば外部SDKの特殊な設定は通常のTuist APIで表現できる。helperが扱わない設定の共存条件や、明示resolutionが各Featureの動作要件を満たすかは統合側で確認する。

## 署名・OS・実行時との境界

Tuistが生成したentitlementsをXcode設定とCIのad-hoc署名の両方で使用する。古い固定entitlementsファイルを別途署名へ渡す経路は削除した。指定値がIPAの署名へ入ることと、SideStore再署名後に許可されること、OSサービスを実際に利用できることは別々に検証する。

この合成はcapabilityを取得せず、プロビジョニングを購入/変更しない。background modeが書けてもscheduler登録・期限・再配送が実装されたわけではなく、権限用途説明があってもFeature別同意は未実装。OSの同意単位はホストアプリのままである。署名依存の必然的な条件と、残るJibunKit実装の仕事を混同しない。

[検証記録](../verification/2026-09-11-feature-build-requirements.md)と、Tuist公式の[コード共有](https://docs.tuist.dev/en/guides/features/projects/code-sharing)、[entitlements](https://tuist.github.io/tuist/main/documentation/projectdescription/entitlements/)を参照。

## 多言語InfoPlist.strings

用途説明はFeatureごとの`localizedInfoPlist[locale][key]`として登録する。同一locale/keyが同値なら保持し、異なる場合はhostが`localizedInfoPlistResolutions`へ最終文言を明記する。空locale/key、未要求locale/keyへのresolutionは拒否する。

```swift
let app = FeatureBuildConfiguration(features: [
    .init(owner: "camera", localizedInfoPlist: [
        "en": ["NSCameraUsageDescription": "Take photos"],
        "ja": ["NSCameraUsageDescription": "写真を撮影します"],
    ]),
    .init(owner: "scanner", localizedInfoPlist: [
        "en": ["NSCameraUsageDescription": "Scan documents"],
        "ja": ["NSCameraUsageDescription": "書類を撮影します"],
    ]),
], localizedInfoPlistResolutions: [
    "en": ["NSCameraUsageDescription": "Use the camera to scan documents"],
    "ja": ["NSCameraUsageDescription": "カメラで書類を撮影します"],
])
let build = try app.compose(infoPlist: hostPlist, entitlements: hostEntitlements)
try build.writeLocalizedInfoPlistStrings(to: "Derived/AppInfo")
```

生成先をtargetの`resources`へ渡すと、Apple標準の`<locale>.lproj/InfoPlist.strings`としてbundleへ入る。appとwidgetは別々のconfiguration・生成先を使い、片方の用途説明や表示名をもう片方へ流用しない。これはFeature UI全体の翻訳frameworkではなく、Info.plistの人向け文字列だけを合成する。
