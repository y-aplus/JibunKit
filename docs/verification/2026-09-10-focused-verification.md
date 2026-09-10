# Focused UI検証経路

更新日: 2026-09-10

## 目的と変更

`build-ios.yml`の`ui_test_filter`はUI suiteを一件へ絞っても、その前に通常のSwift/Moduleテスト、Releaseビルド、IPA梱包、CounterExample、BackupHarnessを実行していた。通知やnavigationの短い診断反復が、Files pickerとは別の準備と通常成果物生成を待つ状態だった。

`focused_ui_validation=true`を明示した場合だけfocused UI検証とし、publication boundary、固定Xcode/Tuist、workspace生成、Simulator準備、選択した一件、診断回収だけを残した。CounterExampleとBackupHarnessは対象テストが直接使う場合だけビルド・導入する。focusedを指定しない通常IPA・全Simulator回帰と、`feature_validation`の生成Feature/Records経路は変更しない。既存の`feature_validation=true`とfilterの併用も従来どおり実行できる。

任意文字列は環境変数でshellへ渡し、`MigrationUITests/<TestClass>/test<TestMethod>`の単一identifier形式と`UITests` source上の存在を検査してから、引用された一引数として`xcodebuild`へ渡す。実行後はXCTest logに指定した一件の`passed`がちょうど一件あることも検査し、存在しないfilterを0件実行の成功として扱わない。focusedと`feature_validation`または`feature_ui_test_filter`の混在、およびSimulatorを要求しないfilter指定は入力エラーにして、省略範囲が曖昧な実行を作らない。

## 実行例と証拠の境界

```bash
gh workflow run build-ios.yml --ref YOUR_BRANCH \
  -f simulator_tests=true -f focused_ui_validation=true \
  -f ui_test_filter=MigrationUITests/MigrationUITests/testNotificationDeliveryAndRouting
```

この成功が示すのは、指定したUI test methodが生成workspaceとiOS 26 Simulator上で成功したこと、およびpublication boundaryを通過したことだけである。次は未実行であり、main統合前、共通契約変更、複数境界の交差、release候補ではfilterなしの適切な回帰を別に行う。

- Swift packageと独立Feature packageのテスト
- Release app/Widgetビルド、App Intents metadata、署名、IPA検査
- 指定外の本体UI、Files backup往復、CounterExample、BackupHarness
- 生成Feature hostとRecordsのビルド・UI検証

## 検証記録

Windowsでは`git diff --check`を実行した。Swift/Xcodeはないため、branch上の[focused run 34482025360](https://github.com/y-aplus/JibunKit/actions/runs/34482025360)、source `e82b1a981e1f145887948db3b9d6e1cc545d42d8`で実行条件と実機能を確認した。

runは2026-09-10 13:20:39–13:32:47 UTCの12分08秒で成功した。publication boundary、入力検査、Xcode/Tuist固定、workspace生成、Simulator準備、`testMiniAppSearchFiltersAndOpensResults`、診断export/uploadが成功した。通常Swift/Moduleテスト、Records/template、Releaseビルド、IPA検査/upload、CounterExample、BackupHarness、Files往復はActionsのstep結果でもskipを確認した。

比較可能な既存の通常Simulator回帰run 34211874205は22分36秒だったため、今回のfocused runは観測値で10分28秒短い。ただし対象UI件数とrunner状態が異なり、固定短縮率や個々のskipだけの寄与は主張しない。このrunでは指定外回帰を意図して実行しておらず、上記「実行例と証拠の境界」の未実行範囲は残る。

レビューで、形式だけ正しい不存在testを`xcodebuild`が0件成功として扱う余地を指摘された。source存在とXCTest成功件数の二段階検査を追加し、Windows上で実在する`testMiniAppSearchFiltersAndOpensResults`と模擬成功logを受理、不存在method、生成host専用`GeneratedFeatureUITests`、0件実行logを終了コード1で拒否することを確認した。通常host focusedと`feature_ui_test_filter`の混在も事前入力エラーにした。
