# JibunKit 0.8.3（出荷候補）

build13。自作Featureの音声・撮影・文書/QRを一つのhostへ接続する基盤を追加します。版変更後の出荷IPA検証待ちで未公開です。1.0は未達です。

- AudioSessionの互換要求の共存、非互換要求の明示切替、停止/復旧待ちを追加。player/recorderや保存データはFeatureが所有します。
- Now Playingのowner別操作配送と終了待ち、camera予約、AVFoundation/VisionKitの寿命/同意/scene管理を追加。
- 全画面スキャナーがhostを隠す際にsceneを誤切断する問題を修正。
- 共有359件（既存Keychain2skip）、native28件、通常通知UIが成功。再生/録音・背景/ロック画面操作/Siri後再開/イヤホン抜去停止・写真/動画/文書/QR・通常版復帰を対象別実機で確認しました。

通常IPAはCounter/Reminder/Shareを含み、診断用メディアFeatureは含みません。既存bundle ID・App Group・保存形式を維持します。音声/撮影Featureはusage description、背景利用宣言、OS許可とFeature別同意を明示して接続してください。

写真初回にエラーを見た可能性の報告があり、全文/再現条件は不明です。その後の写真・動画は成功しましたが、原因解決とは断定しません。0.8.2からのLive B単発値差分も未解明です。全機種/OS、全通話/経路種別、別playerとの実機同時録画、AR/高度同時captureの保証へ一般化しません。

実機sourceは306874f/a142108（0.8.2/build12）。0.8.3そのものの実機確認とは区別し、版番号だけの差分を照合して証拠を再利用します。

[出荷照合](docs/verification/2026-09-17-0.8.3-release.md) ／ [対象別実機](docs/verification/2026-09-16-p2-media-device.md) ／ [音声接続](docs/guides/audio.md) ／ [撮影接続](docs/guides/capture.md)
