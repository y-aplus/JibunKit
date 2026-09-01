# SideStoreで導入・更新する

更新日: 2026-09-01

この手順は、iPhone 16e／iOS 26.6／SideStore 0.6.3と無料Appleアカウントの組合せで確認した。別の端末、OS、SideStore版、Appleアカウントまで同じ結果を保証するものではない。

SideStore自体の導入とpairing fileの準備は[SideStore公式の導入手順](https://docs.sidestore.io/docs/installation/install)に従う。AppbaseIOSのインストール、更新、署名更新を行うときはLocalDevVPNを接続する。

## IPAを用意する

実機用IPAは[ビルド手順](build.md)に従い、GitHub Actionsの`Build iOS IPA` workflowから取得する。成功したrunのartifact `AppbaseIOS-ad-hoc`を展開すると`AppbaseIOS.ipa`がある。

WSLの`xtool dev build --ipa`で作るIPAには公式App Intentsメタデータがないため、Shortcutsを含む実機確認には使わない。Apple Account、パスワード、2FA、証明書、provisioning profileをActionsへ渡す必要はない。

## 初回導入

1. iPhoneでLocalDevVPNを接続する。
2. `AppbaseIOS.ipa`をSideStoreで開き、同じAppleアカウントで署名・インストールする。
3. AppbaseIOSを開き、ミニアプリ一覧が表示されることを確認する。
4. カウンター、Shortcuts、Widget、リマインダー通知を[検証記録](verification/0.1.md)のF1〜F5に沿って確認する。

SideStoreがApp Groupを個人Team向けに書き換える場合、アプリの`Info.plist`に`ALTAppGroups`が追加される。AppbaseIOSは、論理ID`group.com.example.AppbaseIOS.shared`またはその末尾にSideStoreのsuffixが付いた候補を1件だけ選ぶ。Team IDそのものは端末・アカウント固有情報なので、リポジトリや検証記録へ保存しない。

## 更新インストール

保存値を維持したい場合は、既存アプリを削除せず、新しいIPAをSideStoreから上書きする。次の値を変えない。

- 本体bundle ID: `com.example.AppbaseIOS`
- Widget bundle ID: `com.example.AppbaseIOS.Widget`
- App Group: `group.com.example.AppbaseIOS.shared`
- 既存の保存キー: `counter.value`、`reminder.message`

工程2のIPAから工程3のIPAへ上書きし、カウンター値、Widget、Shortcutsを維持したままリマインダーを追加できることを確認済みである。

## 署名を更新する

1. LocalDevVPNを接続する。
2. SideStoreの`My Apps`を開く。
3. AppbaseIOSの右側にある残り日数をタップする。
4. SideStoreが更新成功を表示するまで待つ。
5. AppbaseIOSを開き、保存値と各連携を再確認する。

残り日数はアプリの有効期限を表し、その表示をタップすると対象アプリを手動更新できる。[SideStore公式手順](https://docs.sidestore.io/docs/installation/install)も同じ操作を案内している。

今回の署名更新後は、次を確認した。

- カウンター値とリマインダー内容が残る。
- Widgetが共有値を表示する。
- Shortcutsの「カウンターに追加」が動く。
- 終了状態の通知をタップするとリマインダーが開く。

## アプリ枠・識別子・拡張

AppbaseIOSはSideStoreの`My Apps`上では1つのアプリであり、無料Appleアカウントのactive app枠を1つ使う。SideStore自身もactive app枠を使う。公式FAQでは無料アカウントはSideStoreを含め同時に3アプリ、7日間に10個の異なるアプリ（App IDs）までと説明されている。[SideStore FAQ](https://docs.sidestore.io/docs/faq)

AppbaseIOSのIPAには本体1つとWidget extension 1つが入る。Widgetは別のホーム画面アプリではなく、AppbaseIOSのactive app枠とは別に数えない。App Groupもアプリ枠ではない。一方、署名処理では本体とextensionのbundle ID・profileを扱うため、「1アプリ」「2 bundle IDs」「1 Widget extension」「1 App Group」を同一の数として扱わない。SideStore 0.6.2以降にはextensionへ本体のprofileを再利用する選択肢があるため、アカウント上の実際のApp ID表示はSideStoreの`My Apps`を正とする。

## 保証しない境界

確認済みなのは、同じ端末・Appleアカウント・論理bundle IDでの初回導入、上書き更新、署名更新である。次は別の移行として扱う。

- AppleアカウントやTeamの変更。
- bundle IDやApp Groupの変更。
- AppbaseIOSを削除してからの再導入。
- 端末交換、iOS更新、pairing file再作成後の維持。

SideStore公式手順も、iOS更新や端末リセット等でpairing fileが無効になる場合があるとしている。問題時はアプリを削除する前に、[SideStoreのトラブルシューティング](https://docs.sidestore.io/docs/troubleshooting)と検証記録を確認する。
