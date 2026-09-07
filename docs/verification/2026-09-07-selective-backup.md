# アプリ単位のバックアップ・復元

利用者と、JibunKit全体だけでなく特定アプリだけ戻せることを合意した。選択しなかったFeatureの状態を変更しない。

## 実装順序

- [x] 共通envelope、Feature ID・schema version・任意バイト列payloadを実装。
- [x] 全体形式・ID重複・不正entryを検査し、復元対象を明示選択するAPIを実装。
- [ ] CIで共通形式と選択の回帰テストを検証。
- [ ] Featureごとのexport・復元前検証・適用の接続を追加。
- [ ] Counter／Reminderで独立した復元と失敗時の状態維持を検証。
- [ ] 書出し・読込み・対象選択・上書き確認の画面を追加し、確認可能な範囲で検証。

最初の段階は保存先に一切触れないcodecであり、利用者が画面からバックアップできる状態ではない。次段階まで継続する。

## 形式と責任

外側のJSONはformat `JibunKitBackup`、version 1、createdAt（Foundation Dateの既定Codable表現: 2001-01-01 UTCからの秒数）、entriesを持つ。entryはid、正のschemaVersion、base64のpayload。形式のversionとFeatureのschemaは別である。不明な外側の形式・版、重複ID、不正entryは全体を拒否する。

payloadは任意のバイト列であり、JSONや特定DBに固定しない。内容の検証・旧schemaからの移行はFeatureが担当する。対象外の未導入Featureや未知schemaのpayloadは解釈しない。選択したIDが存在しなければ適用前に失敗する。空の選択は変更なしである。

Dataによる実装はメモリ内で処理し、圧縮・暗号化・ストリーミングはまだ提供しない。大きなメディアやDBを含む実用Featureへの対応を、この段階のcodecだけで保証しない。DBの整合したsnapshot作成や通知予約の復元方針はFeature側と次段階で接続する。全Feature間の原子的復元は現時点では提供しない。
