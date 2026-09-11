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
要求しない。CI実行結果はworkflow hook追加後に追記する。
