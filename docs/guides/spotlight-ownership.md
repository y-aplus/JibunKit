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

この境界は同一process内の協調的な所有権であり、Feature間のセキュリティ境界ではない。

## 検索結果から詳細を開く

通常hostは`CSSearchableItemActionType`のNSUserActivityを受け取り、登録済みFeatureのnamespaceと正しい形式のitem IDだけを`MiniAppRoute`へ戻す。index作成時の`localIdentifier`が、Featureの`MiniAppDefinition.appendDestination`へそのまま渡る。

```swift
appendDestination: { localID, path in
    guard let record = store.record(id: localID) else { return false }
    path.append(RecordDestination(id: record.id))
    return true
}
```

Featureは最新のデータ・権限に基づいて詳細IDを検証する。削除済み等のIDをfalseで拒否した場合、現在の画面を変更しない。未知のFeature、形式不正、検索クエリ継続など別activity typeもこの経路では無視する。データ変更操作は実行しない。

SwiftUIがactivityを渡したsceneへだけ配送し、別windowを選び直さない。選択先Featureの詳細経路は更新するが、同じsceneの他Featureの経路は保持する。OS上の複数windowの割当やcold launchの実行証拠は[検証記録](../verification/2026-09-11-spotlight-routing.md)で区別する。

hostの`NSUserActivityTypes`はCore Spotlightのnative定数から宣言する。独自activity typeを追加するFeatureはbuild requirementsへ配列を登録できるが、そのtypeの受信処理は別途必要。一般のNSUserActivity/Handoffや検索クエリ継続まで自動接続するものではない。
