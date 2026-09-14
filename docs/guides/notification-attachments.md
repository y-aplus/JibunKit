# 通知添付の原本と一時コピー

P1-B実装中。公開0.7.0には含まれず、追加コードのSwift/native検証は未実施。

Appleの[UNNotificationAttachment](https://developer.apple.com/documentation/usernotifications/unnotificationattachment)は、検証した添付をOSの管理領域へ移す。Featureの文書や写真の原本をそのまま渡すと、通常画面が読むファイルを失い得る。`MiniAppNotificationAttachments`は任意の通常ファイルからowner別の一時コピーを作り、そのコピーで標準のnative requestを組み立てるための補助である。独自の添付型や通知機能を制限するwrapperではない。

```swift
let staging = try MiniAppNotificationAttachments(context: context, containerURL: appContainer)
try await coordinator.withStoreAccess(for: context.id) {
    try await staging.withFiles(copiedFrom: [photoURL]) { files in
        let content = UNMutableNotificationContent()
        content.title = "文書の更新"
        content.attachments = [try UNNotificationAttachment(identifier: "preview", url: files[0], options: nil)]
        // request ID/userInfo/categoryは既存のowner namespace/routeで設定する。
        let request = makeOwnedRequest(content: content)
        try await UNUserNotificationCenter.current().add(request)
    }
}
```

`operation`が完了する前に、native登録の完了もawaitする。ファイルを後で使うTaskを起動して先に成功を返してはならない。コピーはMainActorの外で行い、取消時も実際のコピー終了を待ってから解放する。native登録成功後に遅い取消を見て失敗へ変換しない。これは配信成功や原子的な通知の置換を保証するものではない。

コピー先は`Library/Caches/JibunKit/NotificationAttachments/<owner namespace>/<operation UUID>`。同じファイル名の複数添付や複数操作を共有しない。通常終了・エラー・取消時にはその操作のフォルダだけを片付ける。原本とOS管理領域は削除しない。終了時のcache削除失敗やprocess終了で残ったコピーは、ownerの処理をdrainした後に`removeStagingFiles()`で削除できる。他ownerのコピーは保持する。

すでにOSへ渡した添付の削除は、[Appleの仕様](https://developer.apple.com/documentation/usernotifications/unnotificationattachment)どおり対応するpending/delivered requestを`UNUserNotificationCenter`から削除する。Featureの管理削除はまず所有処理を止め、ownerの通知を解除し、その後に準備コピーや業務データを削除する。OS添付URLをキャッシュの掃除対象に混ぜない。取得済み添付の[URLへのアクセス](https://developer.apple.com/documentation/usernotifications/unnotificationattachment/url)にはsecurity scopeが必要。

Foundation試験では原本保持、nativeのmoveに相当する移動、登録失敗・取消・途中コピー失敗の掃除、A削除中のBコピー保持、取消要求後もoperation終了まではコピーを保つことを確認する予定。通常Definitionと実UNUserNotificationCenterの登録/配信/取消、foregroundとaction/text inputはP1-Bのhost fixtureへ接続し、別の受入条件として検証する。
