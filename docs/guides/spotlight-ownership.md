# Core SpotlightのFeature所有権

更新日: 2026-09-10

`MiniAppSpotlightNamespace`は、同じhost indexを使うFeatureへ異なる`uniqueIdentifier`と`domainIdentifier`を割り当てる。local item IDが同じでもFeature IDを含むnamespaceにより衝突せず、Feature全削除は`deleteSearchableItems(withDomainIdentifiers:)`だけを使う。`deleteAllSearchableItems`は他Featureを巻き込むため使わない。

```swift
import CoreSpotlight
import JibunKitCore
import UniformTypeIdentifiers

let spotlight = MiniAppSpotlightNamespace(context: context)
let attributes = CSSearchableItemAttributeSet(contentType: .text)
attributes.title = note.title
attributes.textContent = note.body
try await spotlight.index(localIdentifier: note.id, attributes: attributes, in: hostSpotlightIndex)

try await spotlight.delete(localIdentifier: note.id, from: hostSpotlightIndex)
try await spotlight.deleteAll(from: hostSpotlightIndex)
```

属性をJibunKit独自型へ写さず、native `CSSearchableItemAttributeSet`をそのまま受け取る。item作成時にはnative object全体をcopyし、同じ属性実体をA/Bが再利用しても`CSSearchableItem`によるidentifier/domain設定が別Featureのitemへ波及しない。Featureはcontent type、title、keywords、thumbnail、content URL、ranking等、OSが提供する属性を必要に応じて設定できる。hostはproduction用のcustom `CSSearchableIndex`を一つ用意し、Appleの制約どおり同一indexへの更新を単一taskで直列化する。

この境界は同一process内の協調的な所有権であり、Feature間のセキュリティ境界ではない。検索結果を選んだ後の`CSSearchableItemActivityIdentifier`読取り、`NSUserActivity`からFeature/sceneへのrouting、cold launchは別のD18補完単位である。
