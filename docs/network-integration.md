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

通信を使うTaskをRuntimeへ登録し、取消後の処理終了を待つ。sessionの無効化、delegateが必要とする終了処理、ログアウトに伴う保存層更新はFeatureの所有者から接続する。`invalidateAndCancel()`を呼んだだけで全callbackが完了したとは扱わない。native sessionの終了通知を待つための`MiniAppURLSessionLifetime`を追加した（下記、macOS実HTTP検証済み）。独自delegateの追加解放も終えてから通知を転送し、`onShutdownAsync`へ接続する。[Runtime接続ガイド](runtime-restore-integration.md)も参照。

## 証拠と残件

[MiniAppHTTPIsolationTests](../Tests/JibunKitCoreTests/MiniAppHTTPIsolationTests.swift)はloopback HTTP serverからSet-Cookieを受け、同URLに異なる応答をcacheし、ネットワークを使わない再読出しを比較する。認証challenge・redirect・サーバー側Cookie失効は34432354335で成功。

永続Cookieの明示保存はmacOSの実HTTPとiOSのprocess再起動で確認済み（下記）。パスワード型HTTP認証の明示保存は34437448875でmacOS実HTTPとiOS再起動を検証済み。iOSでの実HTTP送信、process再生成後のdisk cache、background再接続、独自delegateの共有状態は未完。恒久的なログインを必要とするアプリへephemeral化を強制しない。App Group cookie storeは署名で許可されたgroupの共有用であり、任意のFeature名で隔離できるとは扱わない。

D09全体は未達。詳細と各CIは[検証記録](verification/2026-09-10-network-isolation.md)。

## 永続Cookieの明示保存

`let cookies = try MiniAppCookieStore(context: context, profile: "account-1")`はKeychainの保存状態を検証して専用メモリストアへ読み込む。sessionを作る前に`configuration.httpCookieStorage = cookies.storage`を設定する。ログイン応答などの状態変更後に`try cookies.save()`を実行して、成功してから永続保存済みと扱う。

一つのFeature/profileには一つの生存する所有者を置く。同profileの複数所有者が独立にsaveすると古い状態で上書きし得る。全要求が終わるまでsnapshotやclearを始めず、終了時は受付停止→要求完了待ち→saveの順に接続する。`reload`は使用中のCookieを置き換えるため、通常の応答中には呼ばない。

ローカルログアウトは要求を停止してから`try cookies.clear()`を呼ぶ。サーバーがCookieを失効させた場合は、応答完了後のstoreをsaveする。削除のKeychain書込みに失敗したら成功扱いしない。セッション限定Cookieは保存せず、有効期限を過ぎたCookieは読み戻さない。相対Max-Ageを再起動時に延長しないため絶対期限で保存する。

これは自動保存のHTTP層ではない。save以前の強制終了、同profileの多重owner、別processの同時利用は残る。HTTPのパスワード資格情報は別の明示保存adapter（下記）で扱う。Keychainのサイズや保護状態による失敗はthrowする。property list化できないデータや、Foundationで再構築したときに期限・名前・値・domain・path・Secure・HttpOnly・version・portが変わるデータは、以前の保存を置き換える前に失敗させる。これは全Cookie属性の完全な検査ではない。macOSでは期限・破損時の保持・保存データからの再生成とHTTP送信・サーバーlogoutを検証済み。[34433288351](https://github.com/y-aplus/JibunKit/actions/runs/34433288351)ではiOS process再起動後の値・Secure/HttpOnly保持、Aのlogout後もBが保持されることを確認した（111.793秒）。実機、SameSite等の全属性、redirect途中の永続化は未検証。

## 同一Featureの複数アカウントと保存異常

profileはアカウントを識別する安定した文字列を渡す。同じFeatureでもprofileごとにCookie storeとURLSessionを保持する。profile文字列を同じ所有者に固定せず切り替えるだけでは、すでに作ったsessionの接続先storeは変わらない。アカウント切替時に新しいstore/sessionの組へ切り替え、旧sessionの要求が終わるまでその所有者を保持する。

同じserver・Cookie名に三つのprofileでログインし、保存から再生成したsessionのredirect先で各自のCookieを送信、二つを別々にlogoutして残る一つを維持する実HTTP試験を追加した。profileの `/../` や日本語も別のKeychain accountとして扱う。[34435476250](https://github.com/y-aplus/JibunKit/actions/runs/34435476250)でこの実HTTP試験は0.109秒で成功。

不正なarchive・未対応version・相対Max-Ageを含む保存データはreloadでエラーにする。途中まで有効なCookieがあっても、全件を読み終えるまではlive storeを変更しない。読み込み失敗で元の保存データを削除・上書きしない。繰り返すsave/reloadでも元の絶対期限を延長しない試験も追加した。34435476250でこれらの補強とiOSのprocess再起動試験が成功。

## HTTPパスワード資格情報の明示保存

`MiniAppPasswordCredentialStore`はFeature/profile別の専用`URLCredentialStorage`とKeychain snapshotを結び付ける。Cookie storeとは保存serviceも独立しており、片方のclearはもう片方を削除しない。HTTP認証とCookieの両方を使うアプリは、ログアウトで両方を処理する。

```swift
let passwords = try MiniAppPasswordCredentialStore(context: context, profile: "account-1")
let configuration = URLSessionConfiguration.ephemeral
configuration.urlCredentialStorage = passwords.storage
// 必要なら既存のcookies.storage、context.urlCacheも同じconfigurationへ接続する。
let session = URLSession(configuration: configuration)

// Featureの認証フローで得た実際のprotectionSpace、username、passwordを使う。
let credential = URLCredential(user: username, password: password, persistence: .forSession)
passwords.storage.setDefaultCredential(credential, for: protectionSpace)
try passwords.save()
```

saveはこの専用store内の**すべてのパスワードを明示的に永続保存する**。`.forSession`はnative storeに対する寿命指定であり、この明示saveを抑止しない。「保存しない」認証ではsaveを呼ばず、必要なら別の非永続store/sessionを用いる。再生成時は`.forSession`のcredentialを専用storeへ戻す。`.permanent`/`.synchronizable`を使った標準共有Keychainへの保存に置き換えない。

host・port・protocol・realm・認証方式・proxy区分を保持し、同じprotection space内の複数ユーザーと既定ユーザーを復元する。標準の[URLProtectionSpace](https://developer.apple.com/documentation/foundation/urlprotectionspace)で送信対象を決める契約を保つ。sessionを新しく作る前にstoreを割り当てる（[Appleのcredential store仕様](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/urlcredentialstorage)）。独自認証delegateを使う場合も、そのFeatureのstoreへ明示的につなぎ、共有storeへfallbackしない。

ログアウトは新規要求を止め、sessionの終了を待ってから`try passwords.clear()`を実行する。すでに認証済みの接続やdelegateが保持するcredentialはstore削除だけでは失効しない。次の要求は新しいsessionから始める。Runtime終了hookへ接続する場合もこの順序を保ち、保存・削除エラーを成功として隠さない。

読み戻しは全件の形式、重複、既定ユーザーの存在、native protection spaceの再構築を検証してからlive storeを置換する。読出し失敗はlive storeと保存dataを保持し、保存失敗は以前のKeychain snapshotを維持する。Keychainのサイズ・ロック状態・署名による失敗は呼出し側へthrowする。同profileには一つの生存する所有者を置く。

このパスワード型資格情報adapterは、クライアント証明書identity、server trust、SSO、生体認証付き資格情報、同期Keychainを扱わない。基盤全体では[Keychainアクセス制御](guides/keychain-access-control.md)、[Web認証](guides/web-authentication-ownership.md)、[background再接続](guides/background-urlsession-reconnect.md)を別の契約で提供しており、このadapterとの結合検証とは区別する。trust判定やサーバー側ログアウトは変更しない。[34437448875](https://github.com/y-aplus/JibunKit/actions/runs/34437448875)でnativeのhost/port/realm/protocol/proxy/認証方式の区別と複数user、Feature/profileの隔離・Cookie維持・破損時保持、実HTTP Basic challenge（0.057秒）、iOS process再起動（100.041秒）が成功。Digestやproxy認証の実通信は別途残る。

## 要求・delegate完了後の保存とログアウト

`MiniAppURLSessionLifetime`はnative URLSessionの終了通知を待つ部品。Featureの独自delegateへ次の転送を追加する。data/download/authentication等のdelegateはそのまま使える。

```swift
final class FeatureSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    let lifetime = MiniAppURLSessionLifetime()

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task {
            // 独自の非同期解放がある場合は、この転送より前に完了させる。
            await lifetime.didBecomeInvalid(session, error: error)
        }
    }
}

let delegate = FeatureSessionDelegate()
let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
// Featureの入口を閉じ、必要ならRuntimeのowned Taskを取消・joinする。
try await delegate.lifetime.finishAndWait(session)
try cookies.save() // ログアウトならclear。パスワードstoreも必要に応じて処理する。
```

一つのlifetimeは一つのsessionに対応する。他sessionへの使い回しや終了できないshared sessionはエラー。複数の終了呼出しは同じ結果へ合流し、先に届いた終了通知も保持する。待っているTaskが取消されても、資源解放完了を早く報告しない。終わったsessionは再利用せず、新しいsessionとlifetimeを作る。

内部では`finishTasksAndInvalidate()`を一度呼ぶ。これは新しいnative taskの受付を閉じ、既存要求とdelegate呼出しが終わった後の通知を待つ（[Apple仕様](https://developer.apple.com/documentation/foundation/urlsession/finishtasksandinvalidate())）。取消したい場合は、まずRuntime等が所有するTaskを取消してjoinし、その後にこの待機へ進む。外から`invalidateAndCancel()`を呼ぶと同じ完了保証にはならない。[その終了通知は即座に届くとの仕様](https://developer.apple.com/documentation/foundation/urlsessiondelegate/urlsession(_:didBecomeInvalidWithError:))があるため、その通知だけで全処理が完了したとは判定しない。

Runtimeでは`onShutdownAsync`へこの待機と必要な保存・削除を登録する。hookはthrowできないのでエラーをFeatureの状態に保持し、`runtime.shutdown()`後に利用側が確認・報告する。成功扱いして隠さない。[コンパイル対象の接続例・実HTTP試験](../Tests/JibunKitCoreTests/MiniAppURLSessionLifetimeTests.swift)は遅い応答のCookieをdelegate解放後に保存する経路、実行中要求を取消してからログアウトする経路を示す。

delegateの転送漏れ、独自解放が終わらない場合、この待機も終わらない。待機対象のdelegate callback内で同期的にfinishAndWaitの終了を待つと循環待ちになるため、外部のFeature所有者から終了を開始する。別processやbackground sessionの再接続・イベント配送はこの部品だけでは補完していない。iOS runtimeでの終了順序の追加検証は残る。

[34439496158](https://github.com/y-aplus/JibunKit/actions/runs/34439496158)で遅いHTTP応答・delegate追加解放後の保存（0.016秒）、Runtimeの要求取消後のlogoutと他session維持（0.020秒）、先行エラー/重複通知/他session拒否（0.001秒）が成功。共有logic、iOS build/IPA、Feature生成検証も成功。
