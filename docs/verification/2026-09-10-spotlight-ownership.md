# D18 Core Spotlight所有権の検証

更新日: 2026-09-10

## 対象

D18のうち、Core Spotlight itemのFeature別identifier/domainと所有者限定削除を対象とする。検索結果からのhost起動、`NSUserActivity`のFeature/scene routing、cold launchは対象外であり、D18全体を完了扱いしない。

Appleは`CSSearchableItem.uniqueIdentifier`をアプリ内で項目を識別・削除する値、`domainIdentifier`をownerまたは項目群を表してdomain単位削除に使う値と説明している。`CSSearchableIndex`はidentifier/domainによる削除APIと全index削除APIを別に提供し、productionではcustom indexを推奨する。本実装はFeature IDを両identifierへ含め、全index削除を公開しない。

一次資料:

- [CSSearchableItem.uniqueIdentifier](https://developer.apple.com/documentation/corespotlight/cssearchableitem/uniqueidentifier)
- [CSSearchableItem.domainIdentifier](https://developer.apple.com/documentation/corespotlight/cssearchableitem/domainidentifier)
- [CSSearchableIndex](https://developer.apple.com/documentation/corespotlight/cssearchableindex)
- [Searching for information in your app](https://developer.apple.com/documentation/corespotlight/searching-for-information-in-your-app)

## native比較試験

`MiniAppSpotlightTests`はdefault native indexへA/Bが同じlocal IDを持つ二項目を登録する。`CSSearchQuery`で実際のindexから両項目を読み戻し、Feature別unique identifier、domain、native `textContent`を比較する。その後Aのdomainだけを削除し、同じqueryでA消失、Bのidentifier/domain/native属性維持を確認する。cleanupも二domainの限定削除で行い、`deleteAllSearchableItems`へ依存しない。

WindowsにはCore Spotlight/Swiftがないため、実行証拠はApple platform CIで取得する。run 34491161907、source `7c8d5e5`は試験の`contentType`へ文字列を渡してcompileに失敗し、native `UTType.text`へ修正した。

run 34491615457、source `5411ece`は実装と124 testsをcompileし、既存123 testsは成功した。macOS SwiftPM test executableではindex登録APIがエラーなしで完了した後も`CSSearchQuery`が約5秒間0件を返し、A/Bのnative readbackを証明できず対象testを失敗とした。当初は署名条件を疑ったが、後にquery literalを単引用符で囲んでいた誤りを発見したため、環境制約が原因とは判定しない。

生成itemのidentifier/domain/native属性を比較するpure namespace testはmacOSに残す。実indexの登録・読戻し・A限定削除・B再読戻しは`SpotlightOwnershipProbe`と`SpotlightOwnershipUITests`へ移し、通常hostへ含めず、署名済み`feature_validation`隔離hostだけで実行する。selectorは`MigrationUITests/SpotlightOwnershipUITests/testNativeIndexPreservesOtherOwnerAfterOwnedDeletion`。workflow側のoptional fixture接続がmainへ統合されるまでnative比較は未検証であり、本補完単位も完了扱いしない。

run 34492344143、source `ef8efdcd17a32ae24cad1878e03bac7715fdbecd`では署名hostへ進む前のpure namespace testで、同じnative attribute setをA/Bへ渡すと先に生成したA itemまでBのidentifier/domainへ変わることを検出した。`CSSearchableItem`が属性実体へ識別値を反映するため、wrapper内でnative attribute set全体をcopyしてから所有値を設定する。独自属性型へ変換せず、Feature間の参照aliasだけを断つ。

run 34492877334、source `6e8b6bcfdef01614959349467356ea3bc3171bdf`ではpure namespace test、共有124 tests、template/build/IPAが成功し、署名済み隔離hostのprobeも起動した。queryが0件のまま`unexpectedItems`となったため、Appleのquery predicate形式に合わせidentifier literalを二重引用符へ修正した。namespaceが生成するidentifierは引用符を含まない固定形式である。

run 34494850967、source `9ce1771a7197de7a561dcdeca487ed77929de554`でも署名済みprobeのqueryは0件だった。引用符だけが原因ではない。Appleのquery guideはpredicateの属性名を`CSSearchableItemAttributeSet`のproperty（例: `title`）にするよう定めている一方、`uniqueIdentifier`は`CSSearchableItem`自身のpropertyである。そこでUUIDを含むnative `title`で対象を検索し、`CSSearchQueryContext.fetchAttributes`で`title`と`textContent`を取得したうえで、返却itemの`uniqueIdentifier`と`domainIdentifier`を所有権の証拠として比較するよう修正した。

run 34498386522、source `76ef0c24e8bac7f838a933da08b9d502d2d1db6a`ではtitle queryにより期待するidentifier群を読み戻せたが、metadata比較が失敗した。`CSSearchQueryContext`は要求した属性だけを返すため、所有者の証拠に使うnative `domainIdentifier`も`fetchAttributes`へ追加した。

run 34500239424、source `f0428b638b94c98c860a1b0ebb5c1d2ae828236e`はprobeが`running`のままUI testの40秒待機を超えた。取得属性を増やしたqueryの反復時間を考慮してUI待機を90秒へ延ばし、before/after-deleteの実行段階と最終返却itemの詳細が失敗時のaccessibility treeに残るようにした。

run 34502642235、source `3a6ad5d19839e43d6dc1d31bb6b267d5e48aff93`は待機時間内にitem群を読み戻したが`unexpectedMetadata`となった。query contextで明示取得した属性は返却itemのnative `attributeSet`へ格納されるため、domain比較は`CSSearchableItem.domainIdentifier`に加えて`attributeSet.domainIdentifier`も読み、いずれでも同じ所有者値を検証する。
