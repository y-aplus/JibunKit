# 次の実機確認を一つの候補へまとめる準備

まだ実施依頼ではありません。対象は`p2-combined`生成hostで、CI合格・取得IPA照合後に指定します。公開0.8.3を置き換える正式リリースではありません。

## 再試験しない既存成果

f6f6c04で実機確認したHTTP転送のbackground host callback→Feature再接続→保存→completion解放は再利用します。OS継続処理のcode1はnative直接比較でも再現したため、ユーザー指示どおり追加追究を停止します。単なるhost起動をcold HTTP復元や位置イベント起因の起動とは扱いません。単体native試験の成功を実無線や実OS配信へ読み替えません。

## 候補が合格した後のまとまり

| まとまり | 残る実機確認 | 条件 |
| --- | --- | --- |
| iPhone単体 | AR実frame/開始元離脱/停止、ActionのOS入口/入力/取消、代表の用途説明、idle要求と実際の消灯復帰 | AR対応端末。用途説明のためだけに既存全権限を再設定しない |
| iPad | 二windowで別Feature/値を保持、一方の終了で他方を維持 | ユーザーが利用できる時点から。日付だけで利用可能とは判断しない |
| BLE | 自分の制御可能なGATT peripheralとのread/write/notify、片側停止/B維持、背景復帰 | service/characteristic仕様が分かる機器。Heart Rate Measurementへの任意writeで代用しない |
| 位置/iBeacon | 実移動/境界または実beacon受信のうち機器条件が整うもの | 屋内静止やcallback件数だけで背景位置/境界通過を合格にしない |
| CloudKit/APNs | 署名・サービス条件を満たす場合だけ実通信/実OS配信 | entitlementを偽装せず、無料署名での統合smokeと分ける。1.0の判定条件はユーザーへの質問中 |

代表操作は順番に行い、camera/BLE/location/idle/backgroundを同時に動かしたことを暗黙に保証しません。controller/世代/取消race・文字列一致・bundle配置の検査は自動化し、利用者へ精密なタイミング操作や各小変更ごとのIPA入替えを要求しません。まず条件が整ったまとまりだけを読みやすい短い手順で案内します。

## 自動検証の候補

c66b624からCI35300688982を投入。iPad Simulatorで69 native試験と一度のRelease/IPA検査を予定し、完了通知を登録済み。全19 Featureの実host起動登録も確認対象。結果はまだ未判定。
