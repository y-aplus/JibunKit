# Feature内の複数通知ID

更新日: 2026-09-08

実用Featureが予定・レコード単位に通知を持てるよう、MiniAppContextに安定キーからの通知ID生成と所属判定を追加した。既存の単一通知IDと通知タップのpayloadは維持する。キーはUTF-8をBase64へ変換して既存IDの後ろへ追加する。Feature IDの既存のドットescapeと組み合わせ、親子のように見えるFeature IDでも互いの通知を選別しない。

テストは異なるキー・Unicode・空キー・区切り文字、同じキーの再生成、似たFeature ID間の排他性、既存Reminder IDの互換性を扱う。予約処理や一括削除は自動実行せず、Featureが対象を明示してOS APIを使う。

CI実行待ち。新しいAPIはFoundationのみで、URL遷移・バックアップ保存名のUI変更とは独立している。

## CI結果

[run 34173854527](https://github.com/y-aplus/JibunKit/actions/runs/34173854527)、source `66807e402091fbfc19adefa01c22a6552d06e335`で全37件のFoundationテストが成功。複数キーの安定性・一意性、Feature間の所属判定、既存通知IDの互換性を含む。Tuist雛形検証、通常アプリ・Widgetビルド、IPA検査・生成も成功した。

このrunはSimulator UIテストなし。APIの生成・判定とビルドは検証済みであり、複数通知のOSへの予約・配信実績を追加したものではない。
