# JibunKit 0.8.2（公開候補）

build12。Live ActivitiesとAlarmKitをFeatureごとに接続する基盤を追加する中間版です。1.0は未達です。出荷CI・IPA検査・公開は未完です。

- Feature固有の型とnative設定を保つLive Activities/AlarmKit adapterを追加。
- owner別の登録記録、操作の受付・終了待ち、再起動後のOS登録照合を追加。
- 無効化・削除・選択バックアップ復元へ接続し、古い操作を拒否。復元だけでOS活動・予定を勝手に再開しません。
- 独立/統合build・metadata・native/共有試験と、診断版でのOS操作・標準停止callback・片側管理/復元・通常版復帰を確認しました。

Live Bが上書き前に期待230ではなく200と表示された観測が一度あり、原因は未特定です。210へ更新後の再起動やAlarm Aの管理/復元では再現していません。修正済みや操作ミスとは断定せず、P2-5の完全完了判定を残しています。

通常IPAはCounter/Reminder/Shareを含み、診断Featureは含みません。既存の保存ID・App Group・Widget・Shortcutを維持します。AlarmKitは対応OSとアプリ単位の許可が必要です。Focus/silent条件の個別検証、Live表示の永続保証は今回の確認範囲に含めません。

[出荷記録](docs/verification/2026-09-16-0.8.2-release.md) ／ [実機結果](docs/verification/2026-09-16-p2-continuing-surfaces-device.md) ／ [Live Activities接続](docs/guides/live-activities.md) ／ [AlarmKit接続](docs/guides/alarms.md)
