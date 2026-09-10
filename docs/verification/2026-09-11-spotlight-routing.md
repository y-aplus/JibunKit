# D18 Spotlight選択結果の詳細配送

状態: 実装済み、CI待ち。

`MiniAppSpotlightNamespace.localIdentifier`はowner prefixとcanonical Base64/UTF-8を検査してlocal IDを復元する。`MiniAppSpotlightRoute.resolve`はnativeのselected-item activityだけを登録済みFeatureへ解決する。通常hostの`onContinueUserActivity`はSwiftUIが配送したsceneの既存AppNavigationへ渡し、FeatureのappendDestinationによる検証を経てそのownerの詳細経路だけを更新する。

Info.plistのNSUserActivityTypesはCoreSpotlight定数から生成する。独自typeとの合成にはTuist helperの文字列集合処理を追加した。App Intents、検索クエリ継続、一般NSUserActivityの登録/配送はこの補完単位に含めない。

## 検証内容

- native NSUserActivity unit: 同名local IDのowner分離、Unicode/記号/空IDの復元、不正encoding/非UTF-8/別type/不正payload/未登録ownerの拒否。
- Tuist helper: NSUserActivityTypesにFeature要求を追加してもhost typeが保持されること。
- iOS専用の二Feature fixture: 実Core Spotlightへ索引登録しnative queryで可視化を待つ。OSのSpotlight検索UIでA結果を選択→A詳細→Bの既存手動経路保持→host終了後にB結果を選択→B詳細でcold launchを確認する。route resolverを直接呼ぶボタンを代用しない。
- 通常IPA/build、選択した通常host UIと既存Records回帰。

fixtureは既存SpotlightOwnershipProbeのnative query helperを再利用し、一時hostにだけ組み込む。通常IPAに索引作成のテスト画面を含めない。Windowsではdiff・selector・埋込みPythonを検査し、native実行はCIで確認する。

source `ce45761`を[34514127926](https://github.com/y-aplus/JibunKit/actions/runs/34514127926)へ送った。完全selectorは`MigrationUITests/SpotlightRoutingUITests/testNativeSearchOpensOwnerDetailPreservesOtherPathAndColdLaunches`。通常hostは検索/起動回帰を選択。両selectorの存在、diff、実際の埋込みPythonによるfixture両方なし/片方拒否/両方copy・各owner単一登録を確認した。完了はgh run watchからcodex queueへ通知する。

## 初回CIと診断

`34514127926`はgenerated hostの最初の`ready`待ちが30秒で失敗した。build requirements、通常app/widget/IPA buildは成功。検索UIへの移動・結果配送は未到達であり成功扱いにしない。

失敗時の画面は`indexing`。Simulator診断ログでは18:40:40.084にindex-items、同40.199にCSSearchQuery開始が記録されており、索引登録後のquery完了待ちまで進んでいた。既存の成功run `34509301964`はprobe操作からpassedまで約40秒（全体52.529秒）、待機上限90秒だった。新規テストだけ30秒に縮めていたため、上限を既存と揃える。固定sleepは追加せず、failed状態なら即失敗する。fixtureには`querying`状態と登録/検索完了の経過秒を追加し、次の失敗を段階ごとに判別できるようにした。製品の索引APIは変更していない。

## 証拠の境界

再検証はsource `3042cae`の[34516775457](https://github.com/y-aplus/JibunKit/actions/runs/34516775457)。`gh run watch`完了後に親threadへqueue通知する。

待機中のコード確認では、registeredIDs内の不正IDはContext生成前に除外され、未知owner・非canonical Base64・不正UTF-8はresolverがnilを返す。hostはnilで画面を変更せず、有効なIDでもFeatureの`navigationPath(for:)`が拒否した場合はAppNavigationが変更前にreturnする。local IDはURL用文字制限に変換せずopaqueな文字列としてFeatureへ渡す。これはソース確認であり、OS配送や複数window実行の証拠には含めない。

unitの成功はOSが検索結果を表示・配送した証拠ではない。実OS検索UI・cold launch・複数windowの選択はそれぞれ区別して記録する。既存のAppNavigationが保持するのは値ベースの経路であり、任意Viewの内部状態や未保存編集内容全体の復元を保証しない。D18全体は未完。

一次資料: Apple [CSSearchableItemActionType](https://developer.apple.com/documentation/corespotlight/cssearchableitemactiontype)、[onContinueUserActivity](https://developer.apple.com/documentation/swiftui/view/oncontinueuseractivity(_:perform:))。前者のnative userInfoキーと後者のscene配送/NSUserActivityTypes契約に従う。
