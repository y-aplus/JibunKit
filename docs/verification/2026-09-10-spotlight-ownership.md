# D18 Core Spotlight所有権の検証

更新日: 2026-09-10

## 対象

D18のうち、Core Spotlight itemのFeature別identifier/domainと所有者限定削除を対象とする。検索結果からのhost起動、`NSUserActivity`のFeature/scene routing、cold launchは対象外であり、D18全体を完了扱いしない。

Appleは`CSSearchableItem.uniqueIdentifier`をアプリ内で項目を識別・削除する値、`domainIdentifier`をownerまたは項目群を表してdomain単位削除に使う値と説明している。`CSSearchableIndex`はidentifier/domainによる削除APIと全index削除APIを別に提供し、productionではcustom indexを推奨する。本実装はFeature IDを両identifierへ含め、全index削除を公開しない。

一次資料:

- [CSSearchableItem.uniqueIdentifier](https://developer.apple.com/documentation/corespotlight/cssearchableitem/uniqueidentifier)
- [CSSearchableItem.domainIdentifier](https://developer.apple.com/documentation/corespotlight/cssearchableitem/domainidentifier)
- [CSSearchableIndex](https://developer.apple.com/documentation/corespotlight/cssearchableindex)

## native比較試験

`MiniAppSpotlightTests`はdefault native indexへA/Bが同じlocal IDを持つ二項目を登録する。`CSSearchQuery`で実際のindexから両項目を読み戻し、Feature別unique identifier、domain、native `textContent`を比較する。その後Aのdomainだけを削除し、同じqueryでA消失、Bのidentifier/domain/native属性維持を確認する。cleanupも二domainの限定削除で行い、`deleteAllSearchableItems`へ依存しない。

WindowsにはCore Spotlight/Swiftがないため、実行証拠はApple platform CIで取得する。run 34491161907、source `7c8d5e5`は試験の`contentType`へ文字列を渡してcompileに失敗し、native `UTType.text`へ修正した。

run 34491615457、source `5411ece`は実装と124 testsをcompileし、既存123 testsは成功した。macOS SwiftPM test executableではindex登録APIがエラーなしで完了した後も`CSSearchQuery`が約5秒間0件を返し、A/Bのnative readbackを証明できず対象testを失敗とした。Appleはcustom indexの変更を署名済みapp/extensionへ限定しているが、default indexの今回の0件について署名だけが原因とは断定しない。CLI環境の0件を製品挙動や所有権失敗とも扱わない。

生成itemのidentifier/domain/native属性を比較するpure namespace testはmacOSに残す。実indexの登録・読戻し・A限定削除・B再読戻しは`SpotlightOwnershipProbe`と`SpotlightOwnershipUITests`へ移し、通常hostへ含めず、署名済み`feature_validation`隔離hostだけで実行する。selectorは`MigrationUITests/SpotlightOwnershipUITests/testNativeIndexPreservesOtherOwnerAfterOwnedDeletion`。workflow側のoptional fixture接続がmainへ統合されるまでnative比較は未検証であり、本補完単位も完了扱いしない。

run 34492344143、source `ef8efdcd17a32ae24cad1878e03bac7715fdbecd`では署名hostへ進む前のpure namespace testで、同じnative attribute setをA/Bへ渡すと先に生成したA itemまでBのidentifier/domainへ変わることを検出した。`CSSearchableItem`が属性実体へ識別値を反映するため、wrapper内でnative attribute set全体をcopyしてから所有値を設定する。独自属性型へ変換せず、Feature間の参照aliasだけを断つ。
