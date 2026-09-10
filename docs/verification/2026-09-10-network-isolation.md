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

## HTTPでの送信とcache利用

34431373335（source `d9c781d`）でFeature/profile別cacheの値・削除・保存先隔離unitとIPAが成功。次はloopback HTTP fixtureをswift testの間だけ起動し、サーバーからSet-Cookieを受けて各sessionが自分のCookieを送ること、同一URLの異なる応答をそれぞれcache-only要求で取得できること、A削除後もBのCookie/cacheを使えることを確認する。サーバーは127.0.0.1の動的portだけにbindし、外部ネットワークと実認証情報は使わない。fixtureの起動とSet-Cookie応答はWindowsでsmoke確認済み。Swift側はCI待ち。fixture未起動のローカル実行ではこのtestは明示skipし、CIではport設定を必須にする。

34431712192はSwiftのビルド/テスト以前にfixture port待ちで終了した。50回×0.1秒の起動確認の期限内にportファイルが得られなかった。Python初期化のどこで遅れたかまではログから確定できない。固定待ちを増やす代わりに、Pythonがサーバー構築・serveスレッド開始後に環境変数を渡してswift testを起動する構造へ変更した。子テストの終了コードを返し、終了時にサーバーを閉じる。準備成功メッセージと例外の標準ログを残す。HTTPテストの検証待ちは継続。

34431912303（source `072c0e1`）でloopback HTTP testが0.098秒で成功、IPAも成功。次の契約単位としてHTTP Basic同一realm/userのA/B credential分離、同origin redirectのCookie維持、サーバーのMax-Age=0によるAだけの削除を追加し、接続ガイドを作成した。fixture応答のsmokeはWindowsで成功。Swiftの追加経路はCI待ち。

34432354335（source `271b875`）でHTTP auth challenge、redirect、Max-Age=0によるAログアウト/B維持が成功。次の単位はKeychainを利用するMiniAppCookieStoreの明示save/reload/clear。unitはFeature分離・再生成・session-only除外・期限・Secure/path・破損時のlive保持・logout後再生成を扱う。HTTP testはMax-Age Cookieを受けて保存し、別session/storeへ再生成して送信、サーバー失効後のsaveで復活しないことを確認する。実process再起動とは区別する。CI待ち。
