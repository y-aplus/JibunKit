# URLSession共有状態の比較検証

## 調べる差分

別アプリならCookie・HTTP認証・URL cacheはアプリ境界で分かれる。単一hostではURLSessionを別々に作るだけではdefaultの共有Cookieストアを分離できない。

## 公開APIの根拠

- [Apple: httpCookieStorage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage): default/backgroundは共有ストア、ephemeralはメモリ内の専用ストア。
- [Apple: ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral): cache・Cookie・credentialsをディスクへ永続化しない。

## 追加した検証（CI待ち）

二つのephemeral設定に、同じdomain・Cookie名、同じHTTP認証のprotection space/user、同じURLのcacheをそれぞれ異なる値で登録する。片方の削除で他方が消えないことを確認する。default設定のCookieストアが同一objectであることも確認する。sharedへのテスト値の書込みは行わない。

このテストはFoundationストア操作のmacOS baseline。実HTTP要求での送信、iOS、再起動、redirect、認証challenge、background再接続は未検証。ephemeralを採用すればD09完了という判断はしない。永続ログインを失わせる一律ephemeral化は行わず、公開APIで維持できる永続化とFeature単位の所有権管理を引き続き検討する。

## baseline結果とnative cache保存先

34431043696（source `b4cef36`）でdefault共有Cookieの確認とephemeral Cookie/認証/cacheの同一server identity隔離・片方削除が成功。

次にMiniAppContext.urlCacheを追加。明示container配下のLibrary/CachesへFeature namespaceとprofileのSHA-256で保存先を分け、native URLCacheを返す。容量は呼出し側指定で、同profileのcacheは保持して再利用する。既存configurationのCookie/認証設定は変更しない。Appleの[URLCache directory initializer](https://developer.apple.com/documentation/foundation/urlcache/init(memorycapacity:diskcapacity:directory:))を使用する。

unitは二Featureと同Featureの別profileへ同じURLの異なるcacheを置き、片方削除の非干渉と保存先分離を確認する。profileに相対path文字列を使っても保存先の親を変更しない。CI待ち。disk cacheはOSが削除可能な最適化であり、ログインや業務データの永続保存ではない。process再起動時のcache再利用、HTTP経由のcache適用、iOSは別途検証が必要。
