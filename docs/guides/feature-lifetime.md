# Featureの起動・終了と復元

P0-Aの通常・生成CIで非実機条件を確認済み。対象sourceと試験範囲は[P0-A検証記録](../verification/2026-09-12-p0-a.md)を参照する。0.7.0候補の実機確認は未完了。

## 画面と処理の寿命を分ける

`MiniAppFeatureLifetime`をFeatureのIntegrationで一つ所有し、`MiniAppDefinition(lifetime:)`へ渡す。
通常hostはroot生成前に`start()`を待ち、起動失敗の説明と再試行を表示する。
画面切替/disappearでは`stop()`を呼ばない。非選択でも必要な購読・通信・処理は継続する。
SwiftUIの[View.task](https://developer.apple.com/documentation/swiftui/view/task(priority:_:))は画面から離れると取消対象になるため、
画面からの待機とFeature所有の起動処理を分けている。

```swift
@MainActor
let lifetime = MiniAppFeatureLifetime(id: id) { runtime in
    let observations = try runtime.makeNotificationObservations()
    try observations.observe(name: .init("ExampleChanged"), extract: { _ in true }) { _ in
        // Publish this Feature's state on the main actor.
    }
    // Register owned resource cleanup before starting work that uses it.
    // Put blocking file/CPU/database work on its own actor/executor.
    try runtime.onShutdownAsync { await service.close() }
    try runtime.start { await service.processUntilCancelled() }
}
```

`service`はFeatureのサービスを表す。必要ならconfigure内で各世代の接続を作り直す。
MainActor上のconfigureに重い同期処理を置かない。DB/HTTP/購読の所有者をRuntimeへ登録し、
キャンセル後の実際の処理終了・解放まで待つ。単にTask handleをcancelしただけでは閉じたことにしない。

同時startは一つの構成処理を共有する。明示stopは構成の取消を要求し、登録済み資源の解放まで待つ。
構成失敗も登録済み資源の終了を待ってから失敗を返し、再試行は新Runtimeを使う。
`runtime`は起動中/終了中にも存在し得るので、操作開始前の`start()`とRuntimeの受付拒否を尊重する。
このRuntimeを直接shutdownする代わりにlifetime.stopを使う。所有Taskから自分のstopを待つと自己待機になるので外側の調停者から呼ぶ。
非協調処理や主スレッドの同期hangを強制終了する仕組みではない。

## 復元・移行・リセット

通常hostのBackupScreenはDefinitionの`effectiveRestoreLifecycle`を使う。
明示した`restoreLifecycle`があればそれを優先し、なければlifetimeのadapterを使う。
custom adapterはstore固有の失敗回復を含められるが、lifetimeとの接続を自分で維持する。

lifetimeのadapterは復元前に起動していたFeatureだけ再開する。未起動の保存内容を復元しても起動しない。
一時停止中のstartは拒否し、復元途中の通常起動が保存処理へ割り込むことを防ぐ。
applyで取消/失敗が起きても、復帰をcallerの取消で省略しない。復帰失敗は既存の復元失敗表示へ渡す。
一時停止中に明示stopした場合は自動再開を取り消す。

[通常保存と排他保守の入口](store-access-coordination.md)を同じowner/coordinatorへ接続する。
lifetimeだけでは未登録の保存操作を止められず、DB transactionやschema移行を肩代わりしない。
Counter/Reminderの通常Definitionもlifetimeを持つが、OSに予約済みの通知等の登録解除・データ削除とは別の操作。
それらはP0-Bでアプリ内管理へ接続し、非実機条件を確認済みである。候補の実機確認は別に残る。
