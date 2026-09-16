# P2-W 一括実機確認（完了・2026-09-16）

診断source e984d44、通常source4eb784d。CI35027469173のnative/管理UIは成功。通常回帰は差分を確認してCI34979381516の成功jobを再利用する。配布物は公開先から再取得して一致/展開検査済み。両方0.8.0/build10で、実機確認後に版を進める。

- [診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-w-device-check-20260916/JibunKit-P2-W-e984d44.ipa) ／ [診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-w-device-check-20260916/JibunKit-P2-W-e984d44.zip)
- [戻す通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-w-device-check-20260916/JibunKit-normal-4eb784d.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-w-device-check-20260916/JibunKit-normal-4eb784d.zip)

画面名と期待値は会話でも一工程ずつ案内する。GitHubの横長表は使わない。1操作ごとのcommit/pushはせず、異常は工程・表示・前後の操作をまとめて記録する。アプリを削除せず、診断版・通常版のどちらも上書きインストールする。

## 1. 初期状態と配置

診断版を通常版へ上書きインストールする（アンインストールしない）。操作検証Aはsame-id:10、second-id:30、Bはsame-id:20、second-id:40を表示する。既に診断データがある場合は実際の開始値を記録して増分で判定する。Counter/Reminderの値も開始時に控える。

ホーム画面へ操作検証A/BのWidgetを一つずつ追加し、長押しのWidget編集からAはsame-id、Bはsecond-idを選ぶ。Control Centerへ操作検証A/BのControlを一つずつ追加し、Aはsecond-id、Bはsame-idを選ぶ。設定候補はそれぞれ二項目。利用不可や項目未選択の表示は、選択前に限って想定内である。

## 2. 本体を前景にせず四つの入口を操作

AのWidgetを1回押す。Aのsame-idだけが開始値+1。

BのWidgetを1回押す。Bのsecond-idだけが開始値+1。

AのControlを1回押す。Aのsecond-idだけが開始値+1。

BのControlを1回押す。Bのsame-idだけが開始値+1。

初期値から始めた場合、Aは11/31、Bは21/41。各Featureを開き「値を再読込み」で保存値を確認する。表示更新が遅い場合は、保存値が違うのかWidget/Controlだけが遅いのか区別する。短時間の描画遅延だけで保存失敗とはしない。

## 3. 選択変更と再起動後の保持

AのWidgetをsecond-idへ、AのControlをsame-idへ変更する。本体を終了して再起動し、設定が戻らないことを確認する。その後に端末を通常再起動して同じ選択を確認する。各A入口を1回押すと対象だけ+1。Bの選択と値は維持する。同じ診断IPAを上書きし、SideStoreのRefresh後にもアプリを開き、値と4つの選択が保持されることを確認する。

## 4. 項目削除と管理

A本体で「same-idを削除」。same-idを選んでいたAのControlは利用不可となり、古いControlから別項目を変更しない。second-idを選んだAのWidgetは残った項目を操作できる。Bは変更されない。

管理画面でAを無効化。初回にほぼ即時か、数秒か、長く待つかも記録する。Simulatorでは約88秒かかったため、待つ場合は表示も教えてほしい。AのWidget/Controlから更新できず、Bの入口は動く。Aを再有効化するとsecond-idの値を保持し、same-idは復活しない。

管理画面でAを削除して明示的に再登録。Aは初期二項目へ戻る。削除前のA設定/ボタンは新データを操作できず、対象を選び直すと操作できる。Bの値・設定は維持する。

## 5. AだけのJSON復元

バックアップ画面からAだけのJSONを書き出す。AとBをそれぞれ一度更新し、変化後の値を控える。保存したJSONを読み込み、復元対象をAだけにして上書き確認を行う。

Aの値は書出し時へ戻り、Bは復元直前の値を保持する。復元前に設定したAのWidget/Controlは古い世代なので操作を拒否する。Aを再選択した後は再び操作できる。Bの設定はそのまま利用できる。

## 6. 通常版へ戻す

通常製品pathが同一である4eb784dの検証済み通常IPAを上書きインストールする。Counter/Reminderの開始時からの値、既存Counter Widget/Shortcut、通常の書出し/読込み・共有入口を軽く確認する。診断Widgetの旧表示がホームに残る可能性はある。古い配置が残ることと通常IPAに診断コードが含まれることは別で、収録内容はCIのバイナリ検査で判定する。

## 記録

ユーザーの操作結果として全工程を受領。診断IPAはe984d44（0.8.0/build10）、復帰した通常IPAは4eb784d（同版）。直近の端末OS申告はiOS27.0で、今回のやり取りではOS版の再申告は求めていない。以下はCI/直接performから転記した結果ではない。

- 初期値: A10/30・B20/40。各二候補からWidget A=same-id/B=second-id、Control A=second-id/B=same-idを選択し、各1回のOS操作でA11/31・B21/41。
- Controlの設定で一時的に迷った。通常状態の長押しでは設定が開かず、編集状態に入ると期待通り操作できた。未選択時のA/B「利用不可」表示はその後解消。構成変更/再ビルドはしていない。
- Aの選択をWidget=second-id、Control=same-idへ変更し、アプリ終了/再起動後に各1回操作するとA12/32・B21/41。今回と直前の操作は本体の手動再読込みなしでも期待値が表示された。あらゆるタイミングの即時更新保証にはしない。
- 端末再起動、同じ診断IPAの上書き、SideStore Refreshの各段階でA12/32・B21/41と四つの選択を保持。
- A same-id削除後の旧Controlは更新せず、残ったsecond-idはWidgetで32→33。A無効化は「ほとんど即時完了」。無効中A Widgetは更新せず、B Controlはsame-idを21→22。再有効化後Aはsecond-idのみ33、B22/41。実機の即時完了はSimulatorのSpotlight遅延原因解消を意味しない。
- A全体削除/再登録でA10/30、B22/41。古いWidget/Control各1回でAは変わらず、項目を選び直した各1回でA11/31、B22/41。
- AだけJSON書出し後にA Widget/B Controlを各1回操作しA11/32・B23/41。Aだけ上書き復元でA11/31・B23/41。旧設定各1回は更新を拒否し、選び直した各1回でA12/32・B23/41。
- 通常4eb784dへ上書き復帰し、Counter/Reminder保持、通常Counter Widget/既存Shortcut、通常バックアップ書出し/読込みの軽い確認がすべてOK。通常復帰後のOS共有入力や診断surface旧表示の有無は今回独立に確認していない。

この一括確認を受け0.8.1/build11候補へ進む。0.8.1の新IPA自体を実機操作したという意味ではない。版変更後のbuild/IPAは別CIで照合する。
