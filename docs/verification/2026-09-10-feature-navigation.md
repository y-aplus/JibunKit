# Feature別の画面経路保持

状態: 初回CIで切替メニュー非表示を検出し修正。再検証待ち。D04の部分補完。main未統合。

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
