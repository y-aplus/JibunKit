# Feature別の画面経路保持

状態: 修正後の専用UI・通常通知・Records回帰と、購読機構を含む統合sourceの確認が成功。D04の部分補完としてmainへ統合。

## 失われていた境界と変更

同じscene内で別Featureを開くと単一NavigationPathが置換され、元のFeatureの詳細経路へ戻れなかった。AppNavigationにFeature別の値ベースの経路を保持し、hostの切替メニュー・一覧から再開する。scene別の所有構造とprocess通知の一件配送は維持する。

- 切替/一覧表示では各Featureの経路を保持。通常のbackは明示的なunwind、選択中のroot resetは他Featureへ波及しない。
- 明示destinationは対象FeatureのIntegrationが検証後に置換。非対応destinationは現在状態を維持。既存root URL/通知は対象Featureだけrootへ戻す互換動作を保つ。
- Stackをowner切替ごとに更新し、bindingは作成時の世代で検証する。古いstackからの更新は、同じownerに再選択した後も無効。
- CoreのContext/Runtime/Definition契約や他実装レーンのファイルは変更しない。

## 検証計画

CI専用の二Featureで同じInt型のvalue navigationを使い、Aの2段詳細、Bの1段詳細、A再開、native back、一覧経由の再開、A限定reset、B保持、非対応route、Aへの明示route・OS経由root URLとB保持を実際のSwiftUI stackで確認する。専用画面の契約検査では古いbindingの別owner/同ownerへの書戻し拒否とnative popを確認する。

既存の二AppNavigation/通知先選択試験は、一覧からの再開が経路を保持する仕様へ期待値を更新する。通常hostの実通知遷移と通常IPA・Feature生成・共有テストも検証する。限定UI成功を全UI回帰とは扱わない。

## 境界

値ベースの経路保持のみ。View直接指定のNavigationLink、Viewの入力状態、sheet/UIKit状態、process再起動後の保存、OS上の複数window実操作は別の残作業。強制的なCodable化やFeature画面型のhostへの集約はしない。実機確認は未実施。

根拠: [Apple NavigationPath](https://developer.apple.com/documentation/swiftui/navigationpath)と[NavigationStackの状態管理](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack)。公開APIによるvalue pathの保持を使い、任意Viewの状態保存へ効果を拡大解釈しない。

## 初回CIと修正

[34481976643](https://github.com/y-aplus/JibunKit/actions/runs/34481976643)、source `67cd7f2`は生成hostのUI試験で失敗。通常の共有/Featureテスト・iOS Release/IPA・生成hostのコンパイルは通過した。専用画面の古いbinding/owner切替の契約検査と、Aの値ベース2段目への遷移も通過したが、`miniapp.switch.open`が存在しなかった（36.160秒で失敗）。アクセシビリティ階層にはLevel 2と戻るボタンだけがあり、待ち時間不足ではない。

NavigationStackの外へ付けたtoolbarでは詳細画面に共通の切替操作が表示されなかったため、ホスト所有のbottom safeAreaInsetへ移動した。Featureが独自のtoolbarを持っても切替操作を失わず、内容を覆わない。root URL互換性の追加（`aec0786`）も含む最新版で再検証する。初回runでは後続の通常host通知回帰へ到達していない。

## 修正後の検証

[34484074366](https://github.com/y-aplus/JibunKit/actions/runs/34484074366)、source `3e1e5d783a3ef157dba79aaab659359ca1a964f2`が成功。専用のFeature経路保持UIは79.425秒で成功し、同じInt型の詳細経路のA/B切替、native back、一覧から再開、片方だけroot reset、非対応routeの保持、A明示route、OS経由root URLとB保持を確認した。通常hostの実通知遷移62.373秒、Records添付操作96.560秒、Records作成/編集/検索/削除70.564秒も成功。共有114テスト、独立Feature、生成/standalone、通常IPAを確認。限定filterを用いたrunで、全UI suiteの成功ではない。

その後mainへ統合された購読機構（CI34484781329成功）をこのbranchへ取り込み、製品の画面経路の差分がないことを確認した。[34487215191](https://github.com/y-aplus/JibunKit/actions/runs/34487215191)、source `6c7b7cc8092b9a593448863175a0ca111d6558cd`で共有/Feature・iOS build/IPAが成功。二AppNavigation/通知先選択44.823秒、通常hostの検索→遷移→一覧復帰37.028秒、生成standalone 18.768秒、Records添付83.612秒・編集操作60.813秒が成功した。FilesバックアップUIはこのrunでは選択していない。
