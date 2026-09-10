# URLSession共有状態の比較検証

## 調べる差分

別アプリならCookie・HTTP認証・URL cacheはアプリ境界で分かれる。単一hostではURLSessionを別々に作るだけではdefaultの共有Cookieストアを分離できない。

## 公開APIの根拠

- [Apple: httpCookieStorage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage): default/backgroundは共有ストア、ephemeralはメモリ内の専用ストア。
- [Apple: ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral): cache・Cookie・credentialsをディスクへ永続化しない。

## 追加した検証（CI待ち）

二つのephemeral設定に、同じdomain・Cookie名、同じHTTP認証のprotection space/user、同じURLのcacheをそれぞれ異なる値で登録する。片方の削除で他方が消えないことを確認する。default設定のCookieストアが同一objectであることも確認する。sharedへのテスト値の書込みは行わない。

このテストはFoundationストア操作のmacOS baseline。実HTTP要求での送信、iOS、再起動、redirect、認証challenge、background再接続は未検証。ephemeralを採用すればD09完了という判断はしない。永続ログインを失わせる一律ephemeral化は行わず、公開APIで維持できる永続化とFeature単位の所有権管理を引き続き検討する。
