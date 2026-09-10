# D12 Feature URL routing

状態: 下記範囲のCI検証済み。D12全体は未完。

独立時のOS app entry pointに代わり、単一hostへ届いたURLを所有Featureへ解決する。任意の純粋resolverをDefinitionに登録し、未知URLは無視、複数一致は明示failure、唯一の一致だけを元のsceneのAppNavigationへ接続する。Featureは別ownerのIDを返せず、自分のroot/detailだけを返す。

## 検証

- Core: 同scheme/domainのpath別所有者、元URLのquery/fragment保持、任意のdetail識別子、root、未知URL、登録順に依存しない曖昧一致拒否、無効/重複ownerのcallback前拒否、予約schemeとrelative URLの拒否。
- iOS隔離host: `jkrouteprobe` schemeをnative app設定へ登録し、二Featureの冷起動detail、温起動detail、手動で進んだ他ownerの経路保持、曖昧/未知/不正detailの拒否、root指定後の他owner保持を`XCUIDevice.shared.system.open`経由で確認する。
- 通常IPAのRegistryとschemeにはprobeを加えない。`jibunkit://`の既存経路も回帰対象にする。

ローカルWindowsではSwift/Xcodeを実行していない。CI結果とsourceは完了後に追記する。Coreのhttps解析試験は、実Universal LinkのOS配送やweb関連付けの証拠ではない。別アプリの同scheme競合、操作callback、security-scoped file、URL context options、実OS複数windowは未確認。

## CI証拠

[34534795805](https://github.com/y-aplus/JibunKit/actions/runs/34534795805)、source `5747f5e10edf941c1f288795d5cfc364663041c7`、Xcode 26.6で成功。

- Coreの新規4試験と共有159試験が失敗0。登録順によらない曖昧拒否はCoreで決定的に確認。
- `URLRoutingUITests/testCustomURLRoutesColdAndWarmPreservingOtherOwner`は46.997秒で成功。OS経由の独自scheme冷/温起動、所有者のdetail/root、別ownerの手動経路保持を確認。
- 通常hostの`testMiniAppLinksOpenColdAndSwitchWarm`も26.336秒で成功。既存の予約schemeの冷/温起動と不正リンク拒否を回帰確認。
- native requirements/独立package/生成Feature/通常app・Widget/IPAは成功。Records UI stepは成功だがQuick Lookには既知のexpected failureがあり、previewの新たな成功証拠ではない。
- 通常hostの全UI suiteとFiles round tripはこのrunでは実行していない。直前の0.4.0出荷CI 34531391110の証拠とは分ける。
