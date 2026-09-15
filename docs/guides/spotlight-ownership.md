# Core SpotlightのFeature所有権

更新日: 2026-09-14。公開0.7.0と0.8開発中の通常host接続を区別して記載する。

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

属性をJibunKit独自型へ写さず、native `CSSearchableItemAttributeSet`をそのまま受け取る。item作成時にはnative object全体をcopyし、同じ属性実体をA/Bが再利用しても`CSSearchableItem`によるidentifier/domain設定が別Featureのitemへ波及しない。Featureはcontent type、title、keywords、thumbnail、content URL、ranking等、OSが提供する属性を必要に応じて設定できる。上例の`hostSpotlightIndex`には実際に登録と削除で共有するindexを渡す。通常hostが自動で解除する対象は`CSSearchableIndex.default()`であり、custom indexを自動生成する実装ではない。

## 無効化・削除との接続

通常hostはFeatureの新規受付を閉じ、Runtimeを終了してから、default index内のそのFeatureのdomainを削除する。独自の`CSSearchableIndex`を使う場合も禁止しないが、そのindexの所有項目の解除を`MiniAppDefinition.onUnregister`へ接続する必要がある。namespaceが同じだけでは別indexの項目をhostが自動で削除することにはならない。停止対象の書込みはlifetimeへ登録し、解除後に古いwriterが再登録しないようにする。

domain削除のnative完了を待ってから管理状態を確定する。APIが返らない場合に期限超過を成功として扱う仕組みはない。0.8候補のSimulator試験で初回domain削除後に管理が登録解除中のまま120秒を超える事象があった。独立native比較34822983863と同一host比較34823801940は成功し、後者の初回解除は管理の完了表示まで約63秒だった。厳密なcallback時間や以前の超過原因は未確定で、修正済み・Simulator限定とは扱わない。6beb877の実機では初回無効化・再有効化が体感ほぼ即時に完了した。秒数の測定やSimulatorの遅延原因の確定ではない。[実機記録](../verification/2026-09-14-0.8-device-check.md)。[P1-B検証記録](../verification/2026-09-14-p1-b.md)。

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
