# 通信ストアの接続ガイド

## 現在提供できる一式

一時ログインや永続ログインを必要としない通信には、Foundationの専用メモリ内Cookie/credentialストアと、Feature/profile別URLCacheを組み合わせられる。以下の形はmacOSの実HTTP試験でCookie送信・cache-only読出し・他Featureの状態維持を確認している。

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.urlCache = try context.urlCache(
    memoryCapacity: 4 * 1024 * 1024,
    diskCapacity: 32 * 1024 * 1024,
    containerURL: container,
    profile: "account-1"
)
let session = URLSession(configuration: configuration)
```

容量は利用側で決める。Featureの所有者がsessionとcacheを保持し、処理ごとに作り直さない。同一profileでsessionを複数作る場合は、共有したいストアを明示的に同じconfigurationから渡す。別Featureには渡さない。session生成後に元configurationの設定を変えても生成済みsessionの設定を変更する契約ではない。

`URLSession.shared`やdefault設定のままではCookie等の共有が残る。上記もcacheだけディスクを利用できる設定で、Cookie/credentialの永続化は提供しない。

## 所有者の終了と復元

通信を使うTaskをRuntimeへ登録し、取消後の処理終了を待つ。sessionの無効化、delegateが必要とする終了処理、ログアウトに伴う保存層更新はFeatureの所有者から接続する。`invalidateAndCancel()`を呼んだだけで全callbackが完了したとは扱わない。delegate完了まで待つ必要がある資源は、待機を実装して`onShutdownAsync`へ登録する。[Runtime接続ガイド](runtime-restore-integration.md)も参照。

## 証拠と残件

[MiniAppHTTPIsolationTests](../Tests/JibunKitCoreTests/MiniAppHTTPIsolationTests.swift)はloopback HTTP serverからSet-Cookieを受け、同URLに異なる応答をcacheし、ネットワークを使わない再読出しを比較する。認証challenge・redirect・サーバー側Cookie失効は34432354335で成功。

永続Cookieの明示保存は下記の実装を検証中。HTTP認証の永続化、iOS、process再生成後のdisk cache、background再接続、独自delegateの共有状態は未完。恒久的なログインを必要とするアプリへephemeral化を強制しない。App Group cookie storeは署名で許可されたgroupの共有用であり、任意のFeature名で隔離できるとは扱わない。

D09全体は未達。詳細と各CIは[検証記録](verification/2026-09-10-network-isolation.md)。

## 永続Cookieの明示保存（検証中）

`let cookies = try MiniAppCookieStore(context: context, profile: "account-1")`はKeychainの保存状態を検証して専用メモリストアへ読み込む。sessionを作る前に`configuration.httpCookieStorage = cookies.storage`を設定する。ログイン応答などの状態変更後に`try cookies.save()`を実行して、成功してから永続保存済みと扱う。

一つのFeature/profileには一つの生存する所有者を置く。同profileの複数所有者が独立にsaveすると古い状態で上書きし得る。全要求が終わるまでsnapshotやclearを始めず、終了時は受付停止→要求完了待ち→saveの順に接続する。`reload`は使用中のCookieを置き換えるため、通常の応答中には呼ばない。

ローカルログアウトは要求を停止してから`try cookies.clear()`を呼ぶ。サーバーがCookieを失効させた場合は、応答完了後のstoreをsaveする。削除のKeychain書込みに失敗したら成功扱いしない。セッション限定Cookieは保存せず、有効期限を過ぎたCookieは読み戻さない。相対Max-Ageを再起動時に延長しないため絶対期限で保存する。

これは自動保存のHTTP層ではない。save以前の強制終了、同profileの多重owner、別processの同時利用、HTTP資格情報の永続化は残る。Keychainのサイズや保護状態による失敗はthrowする。Cookie属性を失うおそれのある未対応データは保存失敗として扱う。実機と実process再起動、SameSite等の全属性、redirect途中の永続化は未検証。
