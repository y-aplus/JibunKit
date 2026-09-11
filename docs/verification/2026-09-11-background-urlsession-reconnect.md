# Background URLSession再接続の所有権検証

## 対象

D16の最小基盤として、Feature/profile別の安定したbackground session identifier、
画面表示前に登録する再生成factory、host completionの一回性、owner別の取消を追加
する。標準`URLSessionConfiguration.background`、`URLSession`、Feature固有delegateを
置き換えない。既存`MiniAppURLSessionLifetime`と`MiniAppRuntime`の通常session終了
契約も変更しない。

製品hostの共有変更は`NotificationAppDelegate`への
`application(_:handleEventsForBackgroundURLSession:completionHandler:)`追加だけで、
callbackをcore registryへ転送する。FeatureのDefinition/Registry、画面、workflowは
変更しない。製品Registryへ検証用Featureを登録しない。

## 自動検証

`MiniAppBackgroundURLSessionReconnectTests`で次を比較する。

- 同じFeature/profileのidentifier安定性、別owner/profileとの非衝突、復号したowner対応
- 画面生成なしでfactoryを呼び、native background configurationへ同じidentifierを渡す
- 同一sessionへの重複callbackはfactoryを再生成せず同じpending batchへ合流し、native
  delegateのfinishまで全completionを保留してから各一回終了
- `urlSessionDidFinishEvents`相当の`finish()`後は、同じidentifierの次のeventを再接続可能
- 遅延した二回目の`finish()`はhost completionを再実行しない
- A registrationの取消はfuture factoryだけを外し、Aのpending completionはdelegateの
  finishまで保持、Bの接続とcompletionも維持
- A取消後・replacement登録前の同session後着callbackも既存pendingへ結合し、delegate
  finishまでcompletionを保留
- 同じFeature/profileの再登録後、古いregistrationの取消と古いevents tokenが新しい
  factory/pending eventを終了させない
- unknown identifierとfactory失敗でもhost completionを一回解放
- コンパイル可能な標準`URLSessionDelegate` fixtureでcold生成とwarm session/delegate
  再利用の両方を通し、`urlSessionDidFinishEvents`からのみcompletionを解放
- host completionから同期的にwarm再接続しても、delegateが古いtokenを先にproperty
  から外すため新tokenを消さず、次のnative finishまで保持

ここでnative configurationを作る試験とiOS host buildはAPI接続を確認するが、実転送を
発生させるprovider試験ではない。

[GitHub Actions run 34552504692](https://github.com/y-aplus/JibunKit/actions/runs/34552504692)
はsource `9a66cdf3d6de7b39474e5e9725c1f4fe819a59ff`をXcode 26.6で検証し、
新規5試験を0 failureで完了した。共有feature logic、build requirements、独立Feature
packages、通常iOS app/Widget build、arm64・bundle ID・App Group・App Intents・署名・
IPA整合性、artifact uploadも成功した。Simulator UIはこのnative callback接続の検証へ
不要なため実行していない。生成IPAのworkflow内SHA-256は
`21b095df6b5b6e1e642ec0b22aa4b47940e33ec2d6dcdc327fd1e174218a969f`。

統合レビュー後、重複host callbackのcompletionを即時終了する初版契約を修正した。
同じpending eventへ全completionを結合し、native delegateのfinishまで保留する。
registration取消もfuture factoryだけを解除し、進行中completionを早期終了しない。
pendingはevent UUIDを照合して削除するため、旧tokenの遅延finishは新pendingを終了
できない。標準`URLSessionDelegate` fixtureはcold時にsessionを生成し、warm callback
では同じsession/delegateへ新しいevents tokenだけを接続する。

[GitHub Actions run 34553184474](https://github.com/y-aplus/JibunKit/actions/runs/34553184474)
は修正source `768f5048a91ddb6dc669988d5be4ed17036b246b`をXcode 26.6で
検証し、新規6試験を0 failureで完了した。共有feature logic、通常iOS app/Widget
build、署名・IPA整合性、artifact uploadも成功した。workflow内IPA SHA-256は
`70bacf3f7bb7d828c8edec4ff5b847cd4024ba46e1213e338edc20535d2a7bbb`。
この結果も実OS background転送やcold launch配送の実証には読み替えない。

追加レビューで、取消後・再登録前の後着callbackを既存pendingへ結合する順序、
reentrant completionが接続した新tokenをdelegateが消さない転送順、旧tokenの
新pending非干渉、expectationによるnative delegate完了待ちを加えた。
[GitHub Actions run 34553772146](https://github.com/y-aplus/JibunKit/actions/runs/34553772146)
はsource `3fb9dc8c049d52bb0909ec0b0f46573f7979e565`をXcode 26.6で検証し、
新規7試験を0 failureで完了した。共有feature logic、通常iOS app/Widget build、
署名・IPA整合性、artifact uploadも成功した。workflow内IPA SHA-256は
`4ef7901b07ff9b0621c154916baea162ea4cd3752e944d18d9ed73aec18050ce`。

## 未確認境界

OSによるbackground upload/download、アプリ終了後の継続、cold launchでのdelegate
配送、通信失敗からの再試行、SideStore再署名後のidentifier継続は実機未確認。
ユーザーによる強制終了などOS固有の停止条件を内部再接続で迂回できるとは扱わない。
複数の実機項目は今後の出荷候補確認へまとめ、この単位だけの追加実機操作は要求しない。
