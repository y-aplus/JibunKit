# P2-L 一括実機確認（未実施）

診断source5678a41、通常source b1d379b。いずれも0.8.1/build11。0.8.2は実機確認後に版を進める。通常版/Alarm CIと、Live/通常診断host CIは成功。[証拠と限界](2026-09-16-p2-continuing-surfaces.md)。

- [診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-l-device-check-20260916/JibunKit-P2-L-5678a41.ipa) ／ [診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-l-device-check-20260916/JibunKit-P2-L-5678a41.zip)
- [戻す通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-l-device-check-20260916/JibunKit-normal-b1d379b.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-l-device-check-20260916/JibunKit-normal-b1d379b.zip)

アプリを削除せず上書きする。最初にCounter/Reminderの保存値を控える。横長の表は使わず、会話でも一まとまりずつ案内する。個々の返答ごとのpushはしない。異常時はその工程・実際の表示を残し、後続で正常扱いしない。

## 1. Live A/Bの開始とOS操作

「継続表示 A」を開く。初期countは10。「Aを開始」を押す。

「継続表示 B」を開く。初期scoreは200。「Bを開始」を押す。

ロック画面でA/Bそれぞれの継続表示を確認する。Aの「Aを+1」、Bの「Bを+10」を各1回押す。期待はA11、B210。他方を操作したときに自分の値は変わらない。

アプリへ戻って両画面を開き、同じ保存値を確認する。Dynamic Island搭載機では展開表示も確認する。既存データがあれば初期値そのものではなく増分で判定する。

## 2. 再起動・明示終了・片側管理

アプリを終了して再起動し、A/Bの保存値を確認する。OSが活動を保持していれば同じactivity IDで更新でき、新しい活動を重複作成しない。OSが終了させた場合は勝手に新規開始せず、観測した表示/IDを記録する。

Aを終了し、Bの表示と値が残ることを確認する。Aを再び開始してから「ミニアプリ管理」でAを無効化する。Aの表示が終了しBは残る。Aを再有効化すると値は保持するが、活動は自動再開始しない。

Aを明示開始し、管理画面でAだけ削除・再登録する。Aは初期10、活動なし。Bの保存値/活動は保持する。

## 3. Liveの片側復元

Aを開始し、AだけJSONを書き出す。AとBを各1回更新し、復元直前のB値を控える。書き出したJSONを読み込み、復元対象をAだけにして上書きする。

Aは書出し時の値へ戻り、復元前のA活動は終了し、自動再開始しない。Bの値と活動は復元直前の状態を保持する。Aを明示開始した新しい活動から再び更新できる。

## 4. Alarmの許可・タイマー・標準停止

「Alarm A」の「OS許可を要求（app全体）」で許可する。拒否/利用不可/登録失敗が出た場合は全文を記録し、成功へ読み替えない。

Aの「60秒timer」、Bの「90秒timer」を開始する。Aのpause/resumeでAだけが一時停止/再開し、Bへ影響しないことを確認する。OS表示のcountdown/paused/alertの区別も見る。

それぞれ鳴ったらOS画面の標準「停止」を使う。アプリへ戻るとA/Bのstop callbackがそれぞれ開始値+1。Bの服薬値も開始値+1（初期3なら4）。アプリ内stopボタンとは分けて判定する。通常のOS鳴動と、JibunKitが追加配送する業務callbackを両方確認する。

もう一度明示開始でき、終了済登録を永久に再利用しないことを確認してcancelする。

## 5. Alarmの予定・cold復帰・管理・復元

A「5分後」、B「毎日21時」を登録する。Bが近い時刻なら実際の登録時刻を控える。アプリ再起動後も登録が重複せず、AのcancelだけがAを解除しBは残る。繰返し予定を確認後は最後に必ずcancelする。

Aを再登録してAだけ無効化・再有効化する。Aは解除され、自動再登録せず、Bは保持する。Aの業務callback値も保持する。

AだけJSONを書き出し、Aの業務値と予定を変えた後、Aだけ上書き復元する。Aの業務値は書出し時へ戻り、OS予定は解除されて自動再登録しない。Bの業務値/予定は保持する。

Aを明示登録した状態で、Aだけ削除・再登録する。Aは業務初期値・OS予定なし、Bは保持する。

## 6. 上書き・端末再起動・通常版復帰

A/Bに識別できる保存値を作り、同じ診断IPAの上書き、SideStore Refresh、端末再起動で保持を確認する。OS継続表示・予定の残存/終了も実際の状態を記録し、LiveのOS側寿命を永続保証へ読み替えない。

Live活動とAlarm予定を診断画面から終了/cancelしてから、通常IPAを上書きする。Counter/Reminderの値、通常Counter Widget/Shortcut、通常の書出し/読込みを軽く確認する。診断OS面の古い表示が残った場合は有無と押した結果を記録する。

## 結果

未実施。CIのfake/native試験を実機結果へ転記しない。署名/OS制約が疑われる場合は、同じ条件の独立fixtureと比較してから分類する。
