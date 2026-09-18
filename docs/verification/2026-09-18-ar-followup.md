# 0.8.4後のAR診断検証

通常製品は0.8.4のまま。Tests/P2ARのみを拡張し、同一sceneで同一capture coordinatorへ別ownerの実camera要求を送る。Bは診断用で独立Feature登録を持たず、AR診断のruntime/同意/sceneに従属する。従ってFeature管理全体の独立性をこの比較だけで証明しない。

AR起動→B reject/A継続→B stopCurrent/A停止・B camera実稼働→B停止/A暗黙再開なし→A明示再開を1周で判定する。OS interruptionの時刻付き最大80行は観測用で、実callbackが発生しなければ未観測。ホームへ送っただけのscene停止をOS interruption成功には数えない。

自動試験2件を追加。生成host local4試験は成功。既存ar-action境界のnative試験・診断Release/IPAを一回実行し、通常IPA/背景/BLE等の未変更試験を重複実行しない。Files比較CI35335082797は独立して進行中。AR試験が成功しても実cameraとOS中断は実機未確認のまま。

CI35335272799の診断compile失敗（internal scene initializer）は、診断専用dispatcherによる配送へ修正。ddb0f83/CI35336219498でnative17件成功、failure0/skip0、Release/IPA検査成功。実camera競合・OS interruptionは未検証。診断tag p2-ar-followup-20260918を公開し無認証再取得のSHA/CRCを照合。IPA6,246,645 bytes、SHA-256 `75fbc8b81319f7f7f03503b0602ba7a041a549511d11627c65421090aa388532`。通常0.8.4の製品コード変更なし。


## 実機結果

2026-09-18、ユーザーが上記診断IPAの手順1〜5をすべてOKと回答。AR実frame増加、Camera B reject時のA継続、stopCurrentでA停止/B実camera稼働、B停止後A暗黙再開なし、A明示再開後frame増加を確認。sourceはddb0f83で、通常0.8.4の再実機や別Feature管理全体の実証とはしない。OS delegate由来のinterruption/復帰は今回依頼しておらず未観測を維持。

次の境界はBLE cold復元のprocess識別・永続観測の診断整備と、AR OS中断の観測妥当性レビュー。必要な観測がない状態でユーザーへ反復操作を依頼しない。Files独立比較は[別記録](2026-09-18-files-independent-comparison.md)で両bridgeのOS参照解決失敗を確認済み。
