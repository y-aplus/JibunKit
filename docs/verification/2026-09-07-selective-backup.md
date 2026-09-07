# アプリ単位のバックアップ・復元

利用者と、JibunKit全体だけでなく特定アプリだけ戻せることを合意した。選択しなかったFeatureの状態を変更しない。

## 実装順序

- [x] 共通envelope、Feature ID・schema version・任意バイト列payloadを実装。
- [x] 全体形式・ID重複・不正entryを検査し、復元対象を明示選択するAPIを実装。
- [x] CIで共通形式と選択の回帰テストを検証。
- [x] Featureごとのexport・復元前検証・適用の接続を追加。
- [ ] Counter／Reminderで独立した復元と失敗時の状態維持を検証。
- [ ] 書出し・読込み・対象選択・上書き確認の画面を追加し、確認可能な範囲で検証。

最初の段階は保存先に一切触れないcodecであり、利用者が画面からバックアップできる状態ではない。次段階まで継続する。

## 形式と責任

外側のJSONはformat `JibunKitBackup`、version 1、createdAt（Foundation Dateの既定Codable表現: 2001-01-01 UTCからの秒数）、entriesを持つ。entryはid、正のschemaVersion、base64のpayload。形式のversionとFeatureのschemaは別である。不明な外側の形式・版、重複ID、不正entryは全体を拒否する。

payloadは任意のバイト列であり、JSONや特定DBに固定しない。内容の検証・旧schemaからの移行はFeatureが担当する。対象外の未導入Featureや未知schemaのpayloadは解釈しない。選択したIDが存在しなければ適用前に失敗する。空の選択は変更なしである。

Dataによる実装はメモリ内で処理し、圧縮・暗号化・ストリーミングはまだ提供しない。大きなメディアやDBを含む実用Featureへの対応を、この段階のcodecだけで保証しない。DBの整合したsnapshot作成や通知予約の復元方針はFeature側と次段階で接続する。全Feature間の原子的復元は現時点では提供しない。

## 共通形式のCI

[run 34110467189](https://github.com/y-aplus/JibunKit/actions/runs/34110467189)、source `f9b66607f6ac326054c7e84ba3645c786ac16e00`で共通形式のテスト、生成Featureと通常のiOSビルド、IPA検査、Simulator回帰を含む全step成功。

## Feature接続（検証中）

任意登録のMiniAppBackupProviderはexportと、状態を書き換えずに復元操作を準備するprepareを持つ。MiniAppRestorePlanは選択した全件を準備した後だけ適用を開始できる。実行途中の失敗は完了済みIDと失敗IDを返し、後続を実行しない。失敗したFeature内のrollbackはそのFeatureの責任で、全体が巻き戻ったとは報告しない。

CounterはInt、Reminderはメッセージをschema 1のpayloadとして検証してから保存する。Counter復元後はWidgetを更新する。Reminderは保存メッセージを復元し、そのFeatureの古い予約・配信済み通知を取り消す。過去の予約は再配信せず、必要なら画面から新たに予約する。他Featureの通知には触れない。

独立復元・不正payload時の全件無変更・未知schema・適用途中失敗の報告をテストへ追加した。画面は次段階であり未実装。

## 2026-09-08 画面の接続

Tuist移行と実機の簡易確認後、利用者の継続作業指示により画面を実装。ミニアプリ一覧のバックアップ操作から、対象選択・JSON書出し・読込み・復元対象選択・全件検証・上書き確認へ進む。未対応のentryは復元できない旨を表示する。復元対象は読込み時に未選択へ戻す。

security-scoped URLのアクセス期間内にDataを取得し、codec検証が通るまで保存先を変更しない。読込み・snapshot符号化・復元前検証は画面のactor外で処理する。復元途中の失敗では完了済み・失敗対象・未実行を区別して報告する。

CIで画面のコンパイル、未選択時の書出し不可、対象選択後のFiles表示とキャンセル、既存回帰を確認する。書出しファイルを再読込みして復元する実際のUI経路の検証はまだ残る。過去のZaikoでのFiles障害を理由に今回の検証を省略せず、現行経路の証拠で判断する。

## 画面初回CI

[run 34145260295](https://github.com/y-aplus/JibunKit/actions/runs/34145260295)、source `6b8ba6d`。画面のコンパイル・IPA検査・既存UI3件は成功。追加UIテストはFiles画面にCancelラベルのボタンを想定して失敗。回収したUI hierarchyでは保存・ブラウズ・その他とファイル名欄があり、Cancelはない。未選択時の書出し無効と対象選択・Files表示までは成功している。

検証を実際の保存→Counter変更→読込み→復元キャンセルで無変更→再読込み・復元→再起動後のCounter復元とReminder不変へ拡張した。表示されていないCancelボタンの探索は除いた。

## 保存・再読込みCIの切り分け

[run 34146926618](https://github.com/y-aplus/JibunKit/actions/runs/34146926618)、source `097e21a`。書出し完了表示と保存したファイルの一覧表示まで成功。選択直後のDocumentManagerログはFileProvider -1005 / resolver -1012、続いて `didPickDocumentURLs:` へ空の配列を渡そうとした旨を記録している。アプリへURLが届く前で停止しており、復元確認以降は未検証。既存UI3件・ビルド・IPA検査は成功。

同一テストを別のインストール済みiOSランタイムでも実行して環境依存を切り分ける。CIに任意のランタイム指定を追加した。既定の最新ランタイム選択とテストの合否条件は維持する。

## iOS 26.4での再検証

[run 34148070341](https://github.com/y-aplus/JibunKit/actions/runs/34148070341)、source `773095d`。別ランタイムでも同じUIテストの74行目で失敗。17:46:04の `simulator-app.log` にFileProvider -1005、resolver -1012、DocumentManagerの空URL配列が連続して記録された。最新ランタイムだけの問題ではない。書出し・ファイル一覧までは動作するが、選択後にURLをアプリへ渡せていない。

共通ロジック33件、既存UI3件、生成Featureビルド、通常アプリ・WidgetビルドとIPA検査は成功。Counterのみ／Reminderのみの復元、他方の保存値維持、不正な選択payloadで全件無変更、未知schema拒否はロジックテストで検証済み。一方、実際のFiles読込み後の対象選択・上書き確認・キャンセル・再起動後の復元値はUIでは未検証である。テストをスキップして完了扱いにはしない。

[確認用IPAを含むZIP](https://github.com/y-aplus/JibunKit/actions/runs/34148070341/artifacts/10028428752)。実機で確認する場合はCounterのみを書き出し、Counterを変更してから読込み、復元キャンセルで値が維持されること、再読込み・確定後に元の値へ戻りReminderが変わらないことを確認する。以前の実機簡易確認はTuist移行版についてのもので、このバックアップ画面の確認を兼ねない。
