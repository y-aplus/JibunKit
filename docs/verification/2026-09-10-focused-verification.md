# Focused UI検証経路

更新日: 2026-09-10

## 目的と変更

`build-ios.yml`の`ui_test_filter`はUI suiteを一件へ絞っても、その前に通常のSwift/Moduleテスト、Releaseビルド、IPA梱包、CounterExample、BackupHarnessを実行していた。通知やnavigationの短い診断反復が、Files pickerとは別の準備と通常成果物生成を待つ状態だった。

`focused_ui_validation=true`を明示した場合だけfocused UI検証とし、publication boundary、固定Xcode/Tuist、workspace生成、Simulator準備、選択した一件、診断回収だけを残した。CounterExampleとBackupHarnessは対象テストが直接使う場合だけビルド・導入する。focusedを指定しない通常IPA・全Simulator回帰と、`feature_validation`の生成Feature/Records経路は変更しない。既存の`feature_validation=true`とfilterの併用も従来どおり実行できる。

任意文字列は環境変数でshellへ渡し、`MigrationUITests/<TestClass>/test<TestMethod>`の単一identifier形式を検査してから、引用された一引数として`xcodebuild`へ渡す。focusedと`feature_validation`の混在、およびSimulatorを要求しないfilter指定は入力エラーにして、省略範囲が曖昧な実行を作らない。

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

WindowsではSwift/Xcodeを実行できないため、workflow構文と条件の静的検査を行い、branch上のfocused runで実行時間と選択stepを確認する。run URL、source commit、結果は実行後に追記する。
