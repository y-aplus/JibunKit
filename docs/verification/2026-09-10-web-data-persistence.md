# Webデータ保持の比較診断

## 状態

識別子付きWKWebsiteDataStoreのCookie保持は複数runで成功した一方、34379082689でも再起動後missingが再発した。安定解決とは扱わない。同runの選択復元Runtimeテストは49.466秒で成功。

## 次の診断

同一の検証用iOSアプリ内で、識別子付きストアと標準ストアそれぞれにWebViewを保持し、ページ読込完了後、同じdomain・expiry・値のCookieを保存する。標準ストア側はowner別Cookie名を使って診断同士の上書きを避ける。保存直後のread、background移行、process再生成後のreadを比較する。これは別アプリそのものとの比較ではなく、標準ストアとの差分の一次切り分けである。

診断表示にprofile UUID、isPersistent、isSessionOnly、expires、両ストアの読戻し結果を出す。失敗のassertionは維持する。通常IPAに診断は入れない。

## 根拠と限界

[WebKitの公開ヘッダー](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKHTTPCookieStore.h)と[NetworkProcessの保存処理](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/cocoa/NetworkProcessCocoa.mm)を確認。内部flush処理は存在するが、非公開APIを製品から呼び出す対策は採らない。公開mainの実装は現在のSimulator内WebKitと完全に同じとは限らない。

`feature_ui_test_filter`で生成hostの対象testを絞れるようにした。空の場合は既存の全Feature UIテストを維持する。絞ったrunの成功を全回帰成功とは扱わない。

## 比較診断を含む初回run

[34382453375](https://github.com/y-aplus/JibunKit/actions/runs/34382453375)（source `a037462`）は成功。Web保持・他Feature削除後の保持は92.804秒、通常host通知ルーティング44.792秒、Records添付操作102.671秒、編集保持69.406秒で成功。共有ロジック、独立Feature、IPAも成功した。generated hostはWebテストだけに絞っており、全件回帰ではない。

ただしアプリ側printの比較値はActionsログおよびSimulator-text-diagnosticsに収集されていなかった。標準ストア側の保持結果はこの証拠から断定できない。次の検証ではUIテストプロセスが診断ラベルを読み、成功時にもActionsログへ記録する。識別子付きストアの不安定性は未解決として維持する。

## 比較値を取得した回帰

[34385366877](https://github.com/y-aplus/JibunKit/actions/runs/34385366877)（source `a939cdb`）でgenerated host全12件成功。Webテスト87.339秒。ログで両ownerとも保存直後・再起動後にprofile/defaultの値が一致し、sessionOnly=falseを確認した。A削除後はA profileのみmissing、defaultはAを保持し、さらに再起動後もB profile/defaultはBを保持した。過去の失敗原因は未確定で、再現性の問題を解決済みにはしない。
