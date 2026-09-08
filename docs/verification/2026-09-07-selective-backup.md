# アプリ単位のバックアップ・復元

利用者と、JibunKit全体だけでなく特定アプリだけ戻せることを合意した。選択しなかったFeatureの状態を変更しない。

## 実装順序

- [x] 共通envelope、Feature ID・schema version・任意バイト列payloadを実装。
- [x] 全体形式・ID重複・不正entryを検査し、復元対象を明示選択するAPIを実装。
- [x] CIで共通形式と選択の回帰テストを検証。
- [x] Featureごとのexport・復元前検証・適用の接続を追加。
- [x] Counter／Reminderで独立した復元と失敗時の状態維持をロジックテストで検証。
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

## 実機確認と保存名の改善

利用者から書出し・読込みは正常との報告を受けた。SimulatorのFiles障害と区別して実機での成功を記録する。復元キャンセル・選択外データ維持など個別項目の成功までは、この報告から推定しない。

固定の保存名では毎回上書きか別名保存を求められるとの指摘に対応し、書出し開始時の端末のローカル日時を秒まで付けた `JibunKit-backup-yyyyMMdd-HHmmss.json` を既定名にする。暦・数字書式は固定し、画面の再描画では名前を変えない。同じ秒の再書出しや利用者が同じ名前に変更した場合の競合処理はFilesに委ねる。

## 保存名変更のCI

[run 34173407881](https://github.com/y-aplus/JibunKit/actions/runs/34173407881)、source `b56c8caea28c00c2c55de154652054de4a18865d`は成功。共通ロジックテスト、Tuist雛形検証、通常アプリ・Widgetビルド、IPA検査・生成が成功した。このrunではSimulator UIテストを指定していないため、日時付き保存名のFiles上の表示確認まで成功したとは扱わない。後続のURL遷移・複数通知IDはこのsourceには含まれない。

## Filesに依存しない復元UIの検証

2026-09-08、未検証だった読込み後の復元操作を進めるため、独立したBackupHarness app targetを追加した。製品のBackupScreenとBackupDocumentをそのままコンパイルし、デコード済みのバックアップとFeature定義を渡す。製品側は従来どおりRegistryの定義を渡し、Filesから読込む。検証用の起動引数・fixture・画面はTests/BackupHarnessに置き、製品app targetのsource・依存へ含めない。

CounterとReminderの本物のprovider/storeを、製品とは別のテストsuiteへ接続する。UIテストはキャンセルで両方無変更、Counterのみ復元して再起動後も維持、Reminderのみ復元してCounter維持、不正な選択payloadで両方無変更を確認する。加えてReminderの適用だけを意図的に失敗させ、完了済みCounterと失敗対象の表示、Counterだけ更新された実際の保存値を検証する。

この経路はFilesの受渡しを検証したとは扱わない。元のファイル往復テストは残す。差分検査は成功、iOSビルドと新規UI4件はCIへ送る。

CI表示を改善するため、通常UI回帰（復元harnessを含む）とFiles往復を別step・別xcresultへ分離した。前者ではFilesの1件だけを除外し、後者で同じ1件を必ず実行する。通常UIが失敗しても実行可能な場合はFilesを実行し、どちらの失敗もrunのfailureとして残す。continue-on-errorやテスト内容の弱化は行わない。証拠artifactには両方のxcresult・ログ・画面・診断を含める。

### 初回harness CIの修正

[run 34175867945](https://github.com/y-aplus/JibunKit/actions/runs/34175867945)、source `de243e2`は雛形のホスト組込み検証で失敗した。CI内でNotesFeature依存を最初のCore依存リストへ追加していたため、先頭へ加えたBackupHarnessが対象になり、JibunKit本体でNotesFeatureをimportできなくなっていた。ターゲット名JibunKit-Appを明示して依存追加箇所を選ぶよう修正した。ローカルの変換検証でNotesFeatureが本体にだけ1件追加され、手前のharnessが変化しないことを確認。復元UIテストはこのrunでは未実行。

後続run 34175980737も同じ修正前の雛形処理を含む。製品のFeature依存や復元機能の失敗と混同しない。

run 34175980737（source `e6da91c`）も、雛形検証のNotesFeature依存解決エラーだけで停止したことをログで確認した。`fccd7e0`の修正対象と一致する。修正済みrun 34176089108を送付済みのため、同じ修正・再実行を重複して追加しない。
