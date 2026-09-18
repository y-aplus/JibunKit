# JibunKit 0.8.4 — 公開前候補

公開VERSION候補は0.8.4/build14、最新公開版PREVIOUSは0.8.3/build13。まだ公開・main統合していません。1.0.0の完成判定ではありません。

## この版の変更

- Featureごとの背景処理、位置、BLE、外部データidentity/APNsの接続と所有・終了・復帰の基盤。
- 複数windowの生成・配送・終了連携、単一前景ARの接続、任意採用の保存専用Action extension。
- 通常Widgetのen/ja文言、外観/画面点灯要求の接続例、BLEの接続・復元時通知の取りこぼし対策。

これらはFeature作者向け基盤です。通常IPAはCounter/Reminder、WidgetとShareを含み、診断FeatureやAction extensionは含めません。Actionは構成で明示採用した場合のみ追加します。

## 検証済みの範囲

- c66b624の統合native69件と、ARの実frame/離脱停止/再開/停止、ActionのURL/ファイル/取消/片側無効化、idle点灯維持/通常消灯復帰の実機結果。
- fe1a6e5の実BLE read/write/notify、両Feature同時受信、片側停止後の他方維持、scan停止/切断再接続後受信。
- 7e4c740/CI35325946663でnative73件（失敗/skipなし）と共有BLE/window24件。復元GATT索引、早着通知/旧世代拒否、起動待ちbuffer上限を追加自動検証。14分36秒。
- 41c97f1/CI35298791125の通常共有443件（既存Keychain skip2）・Records11件・選択Counter復元/取消/再起動・Reminder保持は当該sourceの証拠。今回版の通常回帰/IPA検査は別途実施します。

## 未確認・制約

- OSによるBLE/background URLSession等のcold起動・復元、通常schedulerの実配送、実移動/境界/iBeacon受信は未確認。単なるホーム復帰やnative fake成功で代用していません。
- iPad実機はsideload環境の準備を見送ったため未確認。実二window検証はiPad Simulatorのみです。
- CloudKit/APNsの実通信は対応署名・サービス条件が必要で未確認。無料署名で全capabilityが利用できるとはしません。
- 継続処理のOS開始はnative直接比較でも受付エラーがあり未確認。以前のLive B単発値差分など、未解明の観測は保持します。
- 同じBLE機器の両owner通信は修正版で成立しましたが、旧不具合の内部原因は併用時ログ不足のため未確定です。

[対象別の実機記録](docs/verification/2026-09-18-p2-combined-device.md)と[出荷準備記録](docs/verification/2026-09-18-0.8.4-release.md)を参照。公開時に候補source/runと配布IPAのSHAを追記します。旧release/tag/assetは変更しません。
