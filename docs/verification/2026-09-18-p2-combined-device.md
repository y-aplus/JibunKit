# P2統合候補の実機確認

対象は`p2-combined`生成host、source `c66b624419b23470881a926d197118293d9bc1b2`。CI合格と公開IPAの再取得照合が完了。公開0.8.3を置き換える正式リリースではなく、AR・Action・idleの代表実機結果を受領済みです。残件は以下に区別します。

## 再試験しない既存成果

f6f6c04で実機確認したHTTP転送のbackground host callback→Feature再接続→保存→completion解放は再利用します。OS継続処理のcode1はnative直接比較でも再現したため、ユーザー指示どおり追加追究を停止します。単なるhost起動をcold HTTP復元や位置イベント起因の起動とは扱いません。単体native試験の成功を実無線や実OS配信へ読み替えません。

## 確認のまとまり

| まとまり | 残る実機確認 | 条件 |
| --- | --- | --- |
| iPhone単体 | AR実frame/開始元離脱/停止、ActionのOS入口/入力/取消、代表の用途説明、idle要求と実際の消灯復帰 | AR対応端末。用途説明のためだけに既存全権限を再設定しない |
| iPad | 二windowで別Feature/値を保持、一方の終了で他方を維持 | ユーザーが利用できる時点から。日付だけで利用可能とは判断しない |
| BLE | 自分の制御可能なGATT peripheralとのread/write/notify、片側停止/B維持、背景復帰 | service/characteristic仕様が分かる機器。Heart Rate Measurementへの任意writeで代用しない |
| 位置/iBeacon | 実移動/境界または実beacon受信のうち機器条件が整うもの | 屋内静止やcallback件数だけで背景位置/境界通過を合格にしない |
| CloudKit/APNs | 署名・サービス条件を満たす場合だけ実通信/実OS配信 | entitlementを偽装せず、無料署名での統合smokeと分ける。1.0の判定条件はユーザーへの質問中 |

代表操作は順番に行い、camera/BLE/location/idle/backgroundを同時に動かしたことを暗黙に保証しません。controller/世代/取消race・文字列一致・bundle配置の検査は自動化し、利用者へ精密なタイミング操作や各小変更ごとのIPA入替えを要求しません。まず条件が整ったまとまりだけを読みやすい短い手順で案内します。

## 自動検証と配布

[CI35300688982](https://github.com/y-aplus/JibunKit/actions/runs/35300688982)はc66b624で成功。iPad Simulatorの69 native試験、failure0/skip0。全19 Featureの実host起動登録とエラーなし、外観5件、built Widget翻訳、用途説明en/jaとWidget非混入、Share/Action/Widget署名とIPA検査を確認。setup/upload込み14分37秒。実無線・tracking・OS Action入口を自動検証済みとはしない。

- [診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-combined-check-20260918/JibunKit-P2-combined-check.ipa): c66b624、6,387,415 bytes、SHA-256 `42fafdd0f36e67562941a885136aac242c7cbfd2da7c120e6c7fe7f7235fc2cd`。
- [戻し用通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-combined-check-20260918/JibunKit.ipa): 41c97f1944c184540c6e297b8e6cf2dfbc5ac52d、4,721,656 bytes、SHA-256 `691e163ae10b29161775cb4f38a6f7afd737b21e7911cca9abf38f911be4e710`。CI35298791125の通常Counter/Reminder版。安定版0.8.3そのものではない。

両IPAとも内部版0.8.3/build13。同じアプリへ上書きする。公開URLの無認証GET、SHA一致、全entry CRCを照合済み。ZIP配布は追加しない。

## 最初の確認（iPhoneだけで実施可能）

1. 診断IPAを上書きし、Counter/Reminderの既存値と一覧が開けることを確認。
2. 「ミニアプリの管理」→AR Probe→カメラ→「このアプリでの利用」を許可。その後「AR Probe」→「AR開始」（iOS許可が出れば許可）。framesが増えれば実frame受信。トップへ戻って再入場した後は止まっており、開始・停止し直せることを確認。描画ビューではないためカメラ映像が表示されなくてもよい。
3. 「受信検証 A/B」を一度開く。外部アプリの共有シート下側のアクション一覧から「JibunKitへ保存」を使用（上段の共有先「JibunKit」とは別）。代表の文字列またはURLをAへ保存・取込みし、Bが増えないことを確認。一度取消して未取込みが増えないことも確認。残るファイル入力とA無効化/B保持は[Action手順](2026-09-18-p2-ar-action-device.md)にまとめる。
4. 「Appearance A」のenvironment=dark、「Appearance B」のenvironment=lightを確認。Aで「画面を点灯し続ける」をオンにしてrequested/effective=trueを確認し、通常の自動ロック時間を超えて消灯しないことを確認。トップへ戻れば通常の自動消灯へ戻ることを確認。自動ロックが「なし」の場合だけ時間設定が必要。試験後は設定を戻す。表示の文字列・sheet・windowの細部は自動試験で確認しているため手作業で繰り返さない。

途中で異常があればそのまとまりを止め、表示を報告する。後続のBLE/iPad/位置は機器と時間の条件が整ってから。同じIPAを維持し、まとまりの最後に通常IPAへ戻す。CloudKit/APNsの1.0判定条件は別質問の回答を待つ。

## 受領した実機結果（統合候補c66b624）

- AR: 初回は`featureConsentDenied(JibunKitCore.MiniAppCaptureResource.camera)`。管理画面のFeature別カメラ同意を許可するとframesが増加し、トップへ戻って再入場すると停止。再開始で増加・明示停止も成功。初回拒否は同意未許可であり、OS権限拒否やAR非対応とは区別する。手順の設定場所を補足した。
- Action: Safari共有シート下側の「JibunKitへ保存」からURLをAへ保存・取込み、B保持。取消後に未取込み件数とA/B内容が増えない。小さいテキストファイルをBへ保存・取込み、A保持。A無効化時にAへ受付不可、Bへの保存・取込みは成功。ユーザーのOKは提示した二択（A非表示または拒否）のどちらかまでは特定していない。
- Idle: Appearance Aの要求をオンにしてrequested/effective=true、通常自動ロック時間を超えて消灯せず、トップへ戻ると通常消灯する一続きの手順にOKを受領。

今回のOKから、別途案内していない外観A/Bのdark/light、Counter/Reminderの更新保持、通常IPAへの復帰、AR無効化・OS割込み、BLE/iPad/実位置受信まで確認済みとはしない。P2全体の完了や正式版公開ではない。
