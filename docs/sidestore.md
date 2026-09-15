# SideStoreで導入・更新する

更新日: 2026-09-14（公開版とmainの構成・検証sourceの整理。SideStore画面を再検証した日ではない）

最新公開版は0.7.0 build8で、一括実機と通常IPA上書き後の保持を確認済み（[結果](verification/2026-09-13-0.7-device-check.md)）。直前の公開版は0.6.0 build7。[公開記録](verification/2026-09-12-0.6-release.md)にIPAのビルド・署名構造・CRC・公開再取得の確認を記載している。0.6.0そのものの新しい実機試験は行っていない。

実機証拠はsourceごとに区別する。0.1.0 build 1→2の上書き・署名更新はiPhone 16e／iOS 26.6／SideStore 0.6.3で確認した[旧版の記録](verification/0.1.md)。2026-09-09にはRecords接続版`afbf4dc`で上書き・署名更新・Widget/Shortcuts/通知・選択復元を確認した[記録](verification/2026-09-09-v1-candidate.md)がある。後者の端末/OS/SideStore版は再報告されておらず、旧環境を転記して断定しない。

SideStore自体の導入とpairing fileの準備は[SideStore公式の導入手順](https://docs.sidestore.io/docs/installation/install)に従う。JibunKitのインストール、更新、署名更新を行うときはLocalDevVPNを接続する。

## IPAを用意する

公開版は[0.7.0のIPA直リンク](https://github.com/y-aplus/JibunKit/releases/download/0.7.0/JibunKit.ipa)から取得でき、外側のActions ZIPの展開は不要。個人Featureを組み込む場合は[ビルド手順](build.md)に従い、成功runのartifact `JibunKit-ad-hoc`内の`JibunKit.ipa`を取得する。

現在はTuist/Xcodeのnative App Intents metadataを含むIPAを使う。旧xtoolのIPA生成経路は廃止済み。Apple Account、パスワード、2FA、証明書、provisioning profileをActionsへ渡す必要はない。

## 初回導入

1. iPhoneでLocalDevVPNを接続する。
2. `JibunKit.ipa`をSideStoreで開き、同じAppleアカウントで署名・インストールする。
3. JibunKitを開き、ミニアプリ一覧が表示されることを確認する。
4. カウンターの保存・Shortcuts加算・Widget表示とリマインダー通知を確認する。バックアップ画面では必要なFeatureの書出し・読込み・復元対象選択を確認し、上書き復元は対象と確認内容を読んでから行う。

SideStoreがApp Groupを個人Team向けに書き換える場合、アプリの`Info.plist`に`ALTAppGroups`が追加される。JibunKitは、論理ID`group.com.jibunkit.shared`またはその末尾にSideStoreのsuffixが付いた候補を1件だけ選ぶ。Team IDそのものは端末・アカウント固有情報なので、リポジトリや検証記録へ保存しない。

## 更新インストール

保存値を維持したい場合は、既存アプリを削除せず、新しいIPAをSideStoreから上書きする。次の値を変えない。

- 本体bundle ID: `com.jibunkit.app`
- Widget bundle ID: `com.jibunkit.app.Widget`
- App Group: `group.com.jibunkit.shared`
- 既存の保存キー: `counter.value`、`reminder.message`

旧0.1.0の実機記録ではbuild 1からbuild 2へ上書きし、カウンター値、リマインダー文面、Widget、Shortcuts、通知を維持できることを確認済みである。

旧称のアプリとJibunKitはbundle IDとApp Groupが異なる別アプリである。旧アプリの保存値はJibunKitへ自動移行せず、JibunKitの更新確認にも旧アプリへの上書きを使わない。

## 署名を更新する

1. LocalDevVPNを接続する。
2. SideStoreの`My Apps`を開く。
3. JibunKitの右側にある残り日数をタップする。
4. SideStoreが更新成功を表示するまで待つ。
5. JibunKitを開き、保存値と各連携を再確認する。

残り日数はアプリの有効期限を表し、その表示をタップすると対象アプリを手動更新できる。[SideStore公式手順](https://docs.sidestore.io/docs/installation/install)も同じ操作を案内している。

旧0.1.0の署名更新後には次を確認した。2026-09-09の追加結果と0.6.0の未実機確認は冒頭のsource別区分に従う。

- カウンター値とリマインダー内容が残る。
- Widgetが共有値を表示する。
- Shortcutsの「カウンターに追加」が動く。
- 終了状態の通知をタップするとリマインダーが開く。

## アプリ枠・識別子・拡張

JibunKitはSideStoreの`My Apps`上では1つのアプリであり、無料Appleアカウントのactive app枠を1つ使う。SideStore自身もactive app枠を使う。公式FAQでは無料アカウントはSideStoreを含め同時に3アプリ、7日間に10個の異なるアプリ（App IDs）までと説明されている。[SideStore FAQ](https://docs.sidestore.io/docs/faq)

公開版0.7.0のIPAには本体1つとWidget extension 1つが入る。mainのP1-A追加とP1診断IPAにはShare Extensionも含み、本体/Widget/Shareの3つのbundle IDを持つ（Shareは`com.jibunkit.app.Share`）。通常IPAでの追加構成は[P1-A記録](verification/2026-09-13-p1-a.md)、配布済み診断IPAとsource別の実機結果は[P1実機手順](verification/2026-09-14-0.8-device-check.md)を参照する。

WidgetやShare Extensionは別のホーム画面アプリではなく、App Groupもアプリ枠ではない。署名処理では本体とextensionのbundle ID・profileを扱うため、app枠・bundle ID数・extension数・App Group数を同一の数として扱わない。SideStore 0.6.2以降にはextensionへ本体のprofileを再利用する選択肢があるため、アカウント上の実際のApp ID表示はSideStoreの`My Apps`を正とする。4e6a3f4（0.7.1/build9）のiOS27.0実機でP1診断版の同IPA上書き・Refresh後のWidget/受信保持と、通常版復帰後のCounter/Reminder・通常Widget/Shortcutを確認済み。0.8.0/build10候補の新IPAは出荷検証中であり、同じIPAそのものを実機試験済みとは記載しない。

## 保証しない境界

実機確認済みの範囲は冒頭に挙げたsourceで、同じ端末・Appleアカウント・JibunKitの論理bundle IDで行った操作である。すべての版の初回導入・上書き・署名更新を保証しない。次は別の移行として扱う。

- AppleアカウントやTeamの変更。
- bundle IDやApp Groupの変更。
- JibunKitを削除してからの再導入。
- 端末交換、iOS更新、pairing file再作成後の維持。

SideStore公式手順も、iOS更新や端末リセット等でpairing fileが無効になる場合があるとしている。問題時はアプリを削除する前に、[SideStoreのトラブルシューティング](https://docs.sidestore.io/docs/troubleshooting)と検証記録を確認する。

## 診断版から通常版へ戻した場合

同じbundle IDのまま通常IPAへ上書きすると、診断Featureは本体一覧からなくなる。ホームに既に置いた診断Widgetは以前の表示のまま残る場合がある（4e6a3f4実機で観測）。通常IPAに診断kind/resourceがないことは検査済みで、残った表示を診断Featureが引き続き動いている証拠とはしない。不要な配置はホームから取り除ける。コード除去と所有データの削除は別で、詳しくは[静的Widgetの接続](guides/package-static-widgets.md#widget型を出荷構成から除いた後)を参照する。
