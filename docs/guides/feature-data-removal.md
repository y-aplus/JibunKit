# Feature所有データを削除する

`MiniAppRemovalProvider`は、Featureが所有する保存データと利用者向け説明を宣言する。削除確認、Featureの停止、通知・検索等の登録解除、owner予約、管理設定の永続化はhost管理層の責任であり、providerはデータ削除だけを行う。

```swift
let provider = MiniAppRemovalProvider(
    id: context.id,
    dataDescription: "保存した項目と添付ファイル"
) {
    try await store.removeOwnedData()
}
```

`removeData`を呼ぶ時点では、同じownerのRuntimeが停止し、通常保存操作がなく、hostが排他予約を保持している。callback内から同じownerの予約を再取得しない。停止・登録解除・予約のいずれかに失敗した場合や、利用者が確認を取り消した場合はcallbackを呼ばない。timeoutを成功扱いして削除へ進めない。

削除対象はFeatureが明示したキーやディレクトリだけに限定する。providerがないFeatureの保存先を推測して削除しない。UserDefaults suiteや共有コンテナ全体の消去は、他Featureのデータを巻き込むため禁止する。

Counterは`counter.value`、Reminderは`reminder.message`に相当するcontext由来キーだけを削除する。削除後にstoreを作り直すとそれぞれ`0`と空文字列を返し、既存schema 1バックアップは引き続き復元できる。Reminderの通知request/category削除とCounterのRuntime終了はhost側の所有解除手順で扱う。

削除はコードをIPAから除く操作ではない。再登録時は初期保存状態から始まり、Feature内同意やOS権限を暗黙に復活させない。
