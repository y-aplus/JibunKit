# Feature privacy manifests

Featureまたは依存SDK自身のtargetに`PrivacyInfo.xcprivacy`を置き、Swift packageでは明示resourceとして登録する。

```swift
.target(
    name: "ExampleFeature",
    resources: [.process("PrivacyInfo.xcprivacy")]
)
```

hostは通常のpackage product dependencyとしてFeatureを組み込む。manifestをhost用の独自辞書へ転記・連結せず、SwiftPM/Xcodeが作るFeature別resource bundleを配布bundleへ保持する。WidgetがそのSDKを直接利用する場合はWidget targetにもproduct dependencyを登録する。利用しないtargetへ申告を複製しない。

Feature削除時は`Project.swift`のpackage dependencyを外し、`tuist generate`と通常のbuildを再実行する。同一project root・同一DerivedDataでも、Xcodeが該当resource bundleを除去し、残るFeature/SDKの`PrivacyInfo.xcprivacy`を保持することを検証済み。追加cleanや独自の清掃処理は不要だった。[clean/incremental比較の証拠](../verification/2026-09-11-privacy-manifest-ownership.md)を参照。

manifestは実際のデータ収集・tracking domain・required-reason APIと一致させる。bundleにファイルが存在してplistとして読めることは配置証拠であり、App Store Connectのprivacy detailsが正しいことやXcode Organizerの集約privacy reportを審査済みにするものではない。
