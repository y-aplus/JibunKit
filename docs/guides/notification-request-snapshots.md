# 通知requestを所有Featureで読む

`onNotificationAction`と`notificationPresentation`のイベントには任意の`requestSnapshot`がある。host delegateは受信した`UNNotificationRequest`をApple標準のsecure codingでメモリ内のDataへ保存し、所有Featureだけへ渡す。単独アプリならdelegateから読めた独自userInfoやcontent、triggerを、統合で失わないための接続である。

```swift
onNotificationAction: { action in
    guard let snapshot = action.requestSnapshot else { return }
    do {
        let request = try snapshot.request()
        let record = request.content.userInfo["recordID"] as? String
        // Featureがrecordの存在・actionとの対応を検証して処理する。
    } catch {
        // Featureのエラー表示/記録へ接続する。
    }
}
```

snapshotは独自のpayload schemaへ変換しない。requestのnative content/title/body/userInfo/category/thread/trigger等を復元する。Dataだけがexecutor境界を渡り、読み出すたびに別のnative objectを復元する。可変userInfoの参照を共有したり、native classへ独自のSendable宣言を付けたりしない。

添付はnative requestの参照であり、添付ファイル自体をコピー・永続化しない。OSのファイル寿命やアクセス条件は変わらない。永続バックアップ形式、通知受信日時、responseのtargetSceneの代替ではない。入力文字列は従来の`userText`で受け取る。

既存のイベント初期化はsnapshot省略可能。native snapshot作成に失敗した場合もhostは従来の配送とcompletionを実行し、エラーを記録する。Featureはnilや復元失敗を処理する。通知routingは既存payload ownerを使い、未知ownerやhandlerなしを別Featureへ転送しない。

Apple: [UNNotificationContent](https://developer.apple.com/documentation/usernotifications/unnotificationcontent)、[userInfo](https://developer.apple.com/documentation/usernotifications/unnotificationcontent/userinfo)、[UNNotificationResponse](https://developer.apple.com/documentation/usernotifications/unnotificationresponse)。
