# Background URLSession実HTTP比較

## 目的

D16の再接続基盤に続き、host起動中のiOS Simulatorで二つのFeature ownerが標準
`URLSessionConfiguration.background(withIdentifier:)`、`URLSessionDownloadDelegate`、
実loopback HTTPを使う比較fixtureを用意する。独自network wrapperや合成URLProtocolで
成功を作らない。

fixtureはA/Bそれぞれ別の安定session identifierとdelegateを作り、同時downloadの応答を
owner別directoryへ移す。Aの二件目をserverで保留し、開始確認後にBのdownloadを開始、
Aのnative taskだけをcancelする。Aが`URLError.cancelled`となる一方でBが正しい内容を
Bのdirectoryへ保存し、両sessionの完了/取消件数が混ざらないことを画面結果で検査する。

既存`Tests/Fixtures/network_server.py`のloopback serverとhold/release gateを再利用する。
fixture appとUITestは通常製品Registry/Definitionへ登録せず、一時Tuist projectとして
生成する。実行toolは`Tools/verify-background-urlsession-native.py`。

## 証拠境界

この試験で実証するのは、hostが起動中のnative background download、owner別destination、
A task取消時のB継続、native delegateへのdownload/complete callbackである。
`urlSessionDidFinishEvents(forBackgroundURLSession:)`はOSがbackground eventを再接続した
場合の完了境界であり、foregroundで開始・完了するだけのrunで呼ばれるとは仮定しない。
合成callbackを実OS配送とは記録しない。

強制終了後の転送継続、cold launch、UIApplicationDelegateへのOS再接続配送、SideStore
再署名後の識別子継続は別段階の実機境界として残す。この単位だけの追加実機操作は
要求しない。

## CI実行結果

- workflow run: [34557071916](https://github.com/y-aplus/JibunKit/actions/runs/34557071916)
- source: `3d548a67001cc9f4ab86607b5657f28571ac537b`
- Xcode 26.6 / iPhone 17 Simulator (iOS 26.5)
- focused native test:
  `BackgroundURLSessionNativeUITests/testTwoOwnersDownloadAndCancellationRemainsScoped`
  — passed、8.863秒
- appの最終結果:
  `passed: a-destination=owner-a b-destination=owner-b a-cancelled b-continued native-downloads=3`
- 比較用の通常UI回帰:
  `MigrationUITests/testMiniAppSearchFiltersAndOpensResults` — passed、27.806秒
- native診断artifact SHA-256:
  `0de973e8f13446949841990b963b1050571298a0db339986f509a45403010cbb`

検証appはシミュレータの通常のアドホック署名を使う。`CODE_SIGNING_ALLOWED=NO`では
別プロセスのbackground transfer serviceが最初のtaskを`NSURLErrorUnknown`で拒否したため、
このfixtureでは署名を無効化しない。

このrunではhost起動中のdelegate配送のみを判定した。
`urlSessionDidFinishEvents(forBackgroundURLSession:)`のOS配送、process終了、cold launchは
発生させておらず、実証済みとは扱わない。
