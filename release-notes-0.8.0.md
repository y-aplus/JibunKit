# JibunKit 0.8.0 — 出荷前の下書き

**未公開・出荷確認中。** 最新安定版は0.7.0。P0を維持したP1全6単位が0.8.0の到達条件。4e6a3f4（0.7.1/build9）の実機再確認を受領し、0.8.0/build10候補の通常build/IPA検査・最終証拠照合・minor文書レビューへ進む。正式0.7.1は公開していない。

## この版へ含める変更

- OS共有シート・外部ファイルの入力を受信先Featureへ保存し、本体の「受信」から取り込む接続。取消、再起動後保持、失敗後の冪等再試行、対象ownerだけの削除を扱う。
- Swift PackageのApp Intents・entity候補と二静的Widgetを、通常保存と無効化・削除へ接続する手順と検証。既存Counterの識別子は維持する。
- ローカル通知の添付原本を保持する一時コピーと、登録・取消・削除時の寿命管理。Feature別のforeground方針と通知操作の通常接続を検証する。
- HTTPの専用Cookie・パスワード資格情報・cacheと、停止後logout・管理削除の接続。`MiniAppFeatureLifetime.withStoppedOperation`で停止後の処理が終わるまで再開・管理を調停する。
- WebViewのCookie/localStorage/IndexedDBとOS Web認証を通常Featureへ接続し、片側取消・削除時の他方保持を検証する。

通常IPAのミニアプリはCounter/Reminderで、汎用Share Extensionを追加する。受信先を持つ独自Featureは`incoming`登録が必要。診断用A/B Feature・Records・ignoredのZaikoを通常IPAへ自動追加しない。

## 現在の検証証拠

[P1-A記録](docs/verification/2026-09-13-p1-a.md)と[P1-B記録](docs/verification/2026-09-14-p1-b.md)にsource・run・各試験の結果・差分再利用を記録している。通常IPA/回帰、独立Packageのmetadata・Widget、共有入力、通常hostの通知・HTTP・Web試験の個別証拠がある。失敗・取消run内の成功methodを、run全体成功とは記載しない。

P1-Bでは初回Spotlight解除が120秒を超えた後、再検証で管理完了表示まで約63秒で成功した。以前の超過原因は未確定で、修正済み・Simulator限定とは断定しない。実機の初回無効化を含めた[一括確認](docs/verification/2026-09-14-0.8-device-check.md)は再確認まで受領済み。遅延原因の確定とは区別する。

## 公開前に確定する項目

- 実機結果は受領済み。失敗直後の未取込み行は明示観測なし、Widgetの単純再起動だけの再試験なし（更新後起動は確認）という範囲をCI証拠と区別し、P0/P1全条件を最終判定する。
- 到達条件に応じた版番号・build番号の更新と、更新後の通常IPA build/metadata/署名・ZIP検査。
- 製品source、IPA source/run、配布物digest、証拠再利用の差分レビュー。
- 現況文書の全件確認と出荷gate、公開後の状態同期。

この下書きには未取得のsource・digestや未確認の実機成功を記入しない。公開時に上記を確定し、実際の変更・検証・制約を示すrelease notesへ更新する。

## 残る範囲

同一process内の強制隔離、任意DB/SDK/extensionの透過統合は提供しない。Feature自身の業務処理や所有資源を、Integrationから保存・寿命・管理へ接続する必要がある。HTTP cacheの永続保持、全Webデータ種別やSSO、Widgetの即時更新等を保証しない。通常版へ戻した後に診断Widgetの旧表示が残ることを実機観測した。通常IPAに診断kind/resourceがないことは検査済みであり、コード除去はホームの配置や所有データの削除を保証しない。

1.0は未達。受領済み[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)の提案を踏まえ、0.8.0完了時にユーザーと正式範囲を確定する。
