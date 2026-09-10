# 通常の保存操作と復元を調停する

Featureの通常の読書きは、`MiniAppRestoreCoordinator.withStoreAccess(for:operation:)`で同じ保存先の復元・snapshotと調停できる。DBを変更したり通常の読書きを一つずつ直列化したりする必要はない。

```swift
let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: context.id) {
    try await database.readCurrentValue()
}

try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: context.id) {
    try await database.updateEntry(entry)
}
```

`database`はFeature所有のactor等、元のエンジンの並行実行契約を満たす保存層である。このAPIは非SendableなDB接続を別executorへ安全に渡す仕組みではない。closureと返却値はSendableであり、MainActor所有の保存層ならそのactorを経由する。

## 受付の契約

- 通常操作同士は同じFeatureでも並行して入れる。DB内部のトランザクション・接続pool・read/write排他はエンジンが管理する。
- 一件でも通常操作が残っているFeatureへの復元・snapshotは、stop/exportを呼ぶ前にConflictを返す。バックアップ画面はデータ使用中として再試行を案内する。
- 復元・snapshot中は同じFeatureの新しい通常操作をConflictで拒否する。他Featureの操作は進められる。
- 受付前に取消済みならoperationを呼ばない。受付後に取消されても、operationが戻る/throwするまで予約を保持する。途中のDB処理を安全に終えるかrollbackする責任は保存層にある。
- 失敗時もoperationの終了で予約を解放する。無期限のqueueや自動再試行は追加しない。通常操作側のConflictは、その操作のUI/呼出元が使用中として扱う。

## 接続時の注意

バックアップprovider/復元planと同じcoordinator・Feature IDを使い、UI、App Intent、同期処理等の入口で漏れなく登録する。呼出元独自のcoordinatorへ分けると共有バックアップとの排他が成立しない。closureから未awaitのTaskやcallbackを起動して即座に戻ると、その後の仕事は保護されない。callback型APIは完了までawaitできる形へ接続する。

既に排他的に実行されるexport、stop、apply、resume、recoverAfterFailedStopの内部から、同じFeatureの`withStoreAccess`を再度呼ぶとConflictになる。これらは予約済みとして低層の保存操作を直接使う。通常操作のclosure内から同じFeatureの復元を呼んでもConflictになり、暗黙の昇格は行わない。

プロセス内の協調契約である。未登録の書込み、別processのWidget writer、旧callback、DBの保持接続や開いたtransactionを自動検出しない。復元前の全接続終了には[restoreLifecycle](../runtime-restore-integration.md)も必要であり、通常操作が0件というだけでファイルを安全に置換できるとは限らない。

[検証記録](../verification/2026-09-11-store-access.md)はnative SQLiteと二Featureの共有画面を対象とする。全DBやD07全体の完成判定にはしない。
