# 0.8.4後のAR診断検証

通常製品は0.8.4のまま。Tests/P2ARのみを拡張し、同一sceneで同一capture coordinatorへ別ownerの実camera要求を送る。Bは診断用で独立Feature登録を持たず、AR診断のruntime/同意/sceneに従属する。従ってFeature管理全体の独立性をこの比較だけで証明しない。

AR起動→B reject/A継続→B stopCurrent/A停止・B camera実稼働→B停止/A暗黙再開なし→A明示再開を1周で判定する。OS interruptionの時刻付き最大80行は観測用で、実callbackが発生しなければ未観測。ホームへ送っただけのscene停止をOS interruption成功には数えない。

自動試験2件を追加。生成host local4試験は成功。既存ar-action境界のnative試験・診断Release/IPAを一回実行し、通常IPA/背景/BLE等の未変更試験を重複実行しない。Files比較CI35335082797は独立して進行中。AR試験が成功しても実cameraとOS中断は実機未確認のまま。
