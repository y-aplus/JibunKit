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
