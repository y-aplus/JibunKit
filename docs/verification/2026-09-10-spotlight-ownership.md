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

WindowsにはCore Spotlight/Swiftがないため、実行証拠はmacOS CIで取得する。成功run、source commit、時間、未実行範囲は実行後に追記する。
