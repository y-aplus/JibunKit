# Feature privacy manifests

Featureまたは依存SDK自身のtargetに`PrivacyInfo.xcprivacy`を置き、Swift packageでは明示resourceとして登録する。

```swift
.target(
    name: "ExampleFeature",
    resources: [.process("PrivacyInfo.xcprivacy")]
)
```

hostは通常のpackage product dependencyとしてFeatureを組み込む。manifestをhost用の独自辞書へ転記・連結せず、SwiftPM/Xcodeが作るFeature別resource bundleを配布bundleへ保持する。WidgetがそのSDKを直接利用する場合はWidget targetにもproduct dependencyを登録する。利用しないtargetへ申告を複製しない。

Feature削除時はpackage dependencyを外す。生成物をclean buildして、該当resource bundleだけが消え、残るFeature/SDKの`PrivacyInfo.xcprivacy`が内容を変えず残ることを確認する。

manifestは実際のデータ収集・tracking domain・required-reason APIと一致させる。bundleにファイルが存在してplistとして読めることは配置証拠であり、App Store Connectのprivacy detailsが正しいことやXcode Organizerの集約privacy reportを審査済みにするものではない。
