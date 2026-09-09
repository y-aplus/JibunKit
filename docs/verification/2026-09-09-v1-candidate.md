# 1.0候補の検証

## Sourceと配布物

- 通常候補: a27a91e2b9e970ee029c8e9e6ef4eefc9284d6e1、1.0.0 build 3。全CI [34311268444](https://github.com/y-aplus/JibunKit/actions/runs/34311268444)は全step成功。共有/Module tests、生成Feature単独・ホスト、通常IPA、バックアップ往復、通知遷移、Records CRUD/添付を実行。Quick Look表示assert一つの既知期待失敗は継続し、自動プレビュー成功とはしない。
- Records接続確認用: afbf4dcbb1ca1cb045d5e0245a551c604a101962。同じ基盤へPackage/product、既存Integration 3ファイル、Registry登録だけを追加。
- 確認用CI: [34311312989](https://github.com/y-aplus/JibunKit/actions/runs/34311312989)成功。通常IPAビルドであり、このrunはSimulator未実行。
- [確認用IPA](https://github.com/y-aplus/JibunKit/releases/download/v1-device-check-20260909/JibunKit.ipa)
- IPA SHA-256: `111eedee9f2c95ab6f649bcc792d0cf97c8576ca5e269e9ba4d6569b692b8889`
- zip全entry検査成功。本体com.jibunkit.app、Widget com.jibunkit.app.Widgetは両方1.0.0 build 3。

正式releaseではない。Zaikoとテストfixtureを含まない。前回の中間確認IPAとは別成果物である。

## 全CI後にまとめて依頼する実機確認

1. 現在のデータをバックアップし、確認用IPAをSideStoreで上書き導入。Counter、Reminder、以前作ったRecordsの保存値と添付が残ることを確認する。
2. CounterのWidget表示とShortcuts加算を確認。SideStoreで署名更新して、保存値・Widget・Shortcutsが引き続き使えることを確認する。
3. Reminderを予約して通知から開く。Recordsは異なるタイトルの記録A/Bを作り、数分後の異なる日時に通知予約する。ホームへ戻り、それぞれの通知から対応する詳細が開くことを確認する。
4. A/Bを再予約してAだけ取り消す。Bは予定どおり通知されることを確認する。
5. Recordsをバックアップし、記録・添付を変更してからRecordsだけ復元する。記録・添付が戻り、Counter/Reminderの値が変わらないことを確認する。復元前のRecords通知は取り消され、別に予約したReminderの通知は残ることを確認する。

通知時刻はOSの配信判断による遅延があり得る。予定どおり表示されなければ通知センターも確認し、配信されない場合と詳細が開かない場合を分けて記録する。実機結果は以下に記録する。最終公開承認は結果と通常配布物が揃ってから別途行う。

## 通常候補IPAの検査

SHA-256: `895e0cdf00f485fd9a32887b8a402feaf4b6c0f9fdef02e3ad1e2493bf0d80f1`。全ZIP entry検査成功、本体・WidgetのIDは従来どおり、両方1.0.0 build 3。上記Records接続IPAとは別ファイル。通常候補にはRecordsを登録していない。実機判断を依頼する段階に進み、正式公開は未実施。

## 実機結果（2026-09-09）

ユーザーが確認用IPAについて依頼した1〜5すべてOKと報告。上書き後のデータ保持、Widget/Shortcuts、署名更新、Records二件の個別通知と対応する詳細遷移、一件だけの取消、記録/添付の選択復元、他Featureの値とReminder通知維持、復元前のRecords通知取消を確認した。端末/OS/SideStoreの現在版は今回改めて報告されていないため、過去版の環境を転記して断定しない。

実機に入れたのはafbf4dcのRecords接続IPAであり、通常候補a27a91eのIPAそのものではない。差分は既存Recordsの接続だけで、共通処理と既存Counter/Reminderは同じ。通常配布IPAの構成は全CIと静的検査で確認。Simulator Quick Lookの既知期待失敗は残り、中間実機と今回の復元確認を自動プレビュー成功へ読み替えない。
