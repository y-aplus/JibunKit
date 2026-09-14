# P1実機後の修正・切り分け

2026-09-15。baseline `e64d24b`、対象はP1-1/2/3。ユーザー結果と手順改善点の正本は[実機手順書](2026-09-14-0.8-device-check.md)。本書は実装/CI記録であり、実機記録を複製・移動しない。公開版0.7.0、0.8未達。

## 一括レビューと実行境界

共有文字列はplain-text適合とNSString変換可能性を同一視していた。UTF-8/UTF-16のnative data representationを読出し、既存オブジェクトprovider・ファイル・取消/drain回帰を維持する。Shortcutsの診断遅延/失敗をownerの永続storeへ移し、再生成したstoreで一度だけ消費する。管理削除で制御も消す。実機の停止操作に20秒の猶予を設けるが、OS実行での実証は次の候補で必要。

URL enqueueは現エラー番号だけでは原因未確定。Coreのエラーに安定した説明を付け、通常hostの実App Groupでprovider→enqueue→再読込を確認する。保存先の安全検査やowner admissionを根拠なく迂回しない。Widgetは配布IPAに両kind・コード・resourceが存在したので、未収録との初期推測は棄却。通常hostのgalleryと旧構成への上書きを次の検証対象にする。

今回の対象差分をまとめた切り分けCIは`native-surface.yml`の`surface=p1-input-repair`、`simulator_runtime=''`。一run内の独立incoming/intents jobで実行し、どちらかの失敗で他方を中断しない。

- incoming（見込み8分、上限30分）: 既存IncomingNativeTests全件、新規data-only UTF-8/UTF-16と実App Groupへの一括enqueue。Share ExtensionのOS UIはこれだけで合格にしない。
- intents（見込み25分、上限30分）: 単独/統合の既存metadata比較、native Intent/entity/query/管理/取消/失敗、再生成storeへの診断制御伝播。既存OS直接操作を代替したとは扱わない。

前回までの11runを維持し、今回の実機NG後は最大3runを追加予算とする。最初は上記の原因切り分け、次に結果を反映した通常/診断候補とgallery/OS受信を一括、3回目は必要な修正時だけ。成功run数を増やす目的の再実行や子CIは行わない。実機から既に原因不明が見つかったため、3失敗を待たず切り分けを先行する。

ローカルでP1 host構成18件・Intent identity tool4件が成功。workflow YAMLの解析とdiff check成功。WindowsではSwift/Xcodeを実行しておらず、コード修正はCI待ち。確認済みHTTP/Web/通知とP0実機は元sourceを保持し、今後の候補への適用は差分レビューする。0.8には昇格しない。実機確認を区切りに版を進める指示に従い、P1全条件が閉じなければ次の公開は0.7.1として版変更・通常出荷検証を行う。

## 残件

切り分けCI結果、Widget gallery/上書き、新しい候補でOS Shareの成功/取消/再試行とShortcuts制御の確認、必要回帰・配布整合性・文書再確認。今は追加実機操作を依頼しない。過去の58件レビューはそのcommitの記録であり、本変更後の出荷確認にそのまま転用しない。
