# Background URLSession再接続

background URLSessionは通常画面や`MiniAppRuntime`の寿命とは別にOSから再接続を
要求されます。Featureは安定したprofile名を決め、host起動時にfactoryを登録して
ください。画面の`onAppear`から登録してはいけません。

```swift
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    @MainActor var backgroundEvents: MiniAppBackgroundURLSessionEvents?

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            backgroundEvents?.finish()
            backgroundEvents = nil
        }
    }
}

@MainActor
final class DownloadConnection {
    private var registration: MiniAppBackgroundURLSessionRegistration?
    private var session: URLSession?
    private let delegate = DownloadDelegate()

    func registerAtHostLaunch(context: MiniAppContext, profile: String) throws {
        registration = try MiniAppBackgroundURLSessionReconnectRegistry.shared.register(
            context: context,
            profile: profile
        ) { [weak self] identifier, events in
            guard let self else { throw ConnectionError.released }
            let configuration = URLSessionConfiguration.background(
                withIdentifier: identifier
            )
            delegate.backgroundEvents = events
            session = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )
        }
    }
}
```

`profile`はアカウント等を識別する安定した非空文字列です。同じFeature/profileから
同じidentifierが生成され、別Featureまたは別profileとは衝突しません。作成済みの
background sessionに使ったprofileをアプリ更新のたびに変えないでください。

hostの`UIApplicationDelegate`はOSの
`handleEventsForBackgroundURLSession`をregistryへ渡します。registryは対応factoryを
画面なしで呼び、host completionを`MiniAppBackgroundURLSessionEvents`が所有します。
Featureの既存delegateはdownload/data/authentication等を従来どおり処理し、最後の
`urlSessionDidFinishEvents(forBackgroundURLSession:)`から`finish()`を一度転送します。
completionをsession生成直後に呼んではいけません。

同じidentifierへの重複host callbackは後着completionだけを即時終了し、処理中の
接続を奪いません。`finish()`は一回だけ有効で、完了後は同じidentifierの次のOS
callbackを受け付けます。registrationの取消はそのFeature/profileのpending
completionだけを終了し、別ownerを取消しません。Feature固有の転送取消はFeatureが
native task/sessionへ行い、このregistryを全Feature共通の取消スイッチとして使わない
でください。

この基盤はOSがbackground転送を実行する時刻、強制終了後の継続、ネットワーク条件、
再起動配送を保証しません。provider/unit試験とiOS buildはowner routingとnative API
接続の検証であり、実際のOS転送・cold launch配送の実機証拠ではありません。

