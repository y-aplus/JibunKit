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
- 同一sessionへの重複callbackは処理中factoryを再生成せず、後着completionだけ一回終了
- `urlSessionDidFinishEvents`相当の`finish()`後は、同じidentifierの次のeventを再接続可能
- 遅延した二回目の`finish()`はhost completionを再実行しない
- A registrationの取消はAのpending completionだけを終了し、Bの接続とcompletionを維持
- unknown identifierとfactory失敗でもhost completionを一回解放

ここでnative configurationを作る試験とiOS host buildはAPI接続を確認するが、実転送を
発生させるprovider試験ではない。

[GitHub Actions run 34552504692](https://github.com/y-aplus/JibunKit/actions/runs/34552504692)
はsource `9a66cdf3d6de7b39474e5e9725c1f4fe819a59ff`をXcode 26.6で検証し、
新規5試験を0 failureで完了した。共有feature logic、build requirements、独立Feature
packages、通常iOS app/Widget build、arm64・bundle ID・App Group・App Intents・署名・
IPA整合性、artifact uploadも成功した。Simulator UIはこのnative callback接続の検証へ
不要なため実行していない。生成IPAのworkflow内SHA-256は
`21b095df6b5b6e1e642ec0b22aa4b47940e33ec2d6dcdc327fd1e174218a969f`。

## 未確認境界

OSによるbackground upload/download、アプリ終了後の継続、cold launchでのdelegate
配送、通信失敗からの再試行、SideStore再署名後のidentifier継続は実機未確認。
ユーザーによる強制終了などOS固有の停止条件を内部再接続で迂回できるとは扱わない。
複数の実機項目は今後の出荷候補確認へまとめ、この単位だけの追加実機操作は要求しない。
