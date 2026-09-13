# 公開・release手順

更新日: 2026-09-12。最新公開版はGitHub Releasesを正本とする。0.6.0を公開済み。版の対象範囲は[Issue #5の優先実装](implementation-priorities.md)、補完責任は[共存原則](coexistence-boundaries.md)、現状は[差分台帳](coexistence-ledger.md)で判断する。
0.7.0出荷候補のP0はCIと一括実機を確認済み。直前公開版0.6.0との区分・配布状態は[出荷記録](verification/2026-09-13-0.7-release.md)を参照。

## 版ごとの出荷判断

2026-09-12のユーザー指示で実装を再開。過去の[停止時引継ぎ](verification/2026-09-12-development-checkpoint.md)を保持し、以下の版境界で進める。

0.xは検証済みの機能のまとまりを公開する中間版。2026-09-10のユーザー依頼により、着実な開発を続けながら適切な区切りで0.xを公開する。1.0の未達を明記し、未対応・未調査を出荷済み機能へ数えない。既存release/tagの差し替えはしない。

P0の6単位完了が0.7.0、P0を維持したP1の6単位完了が0.8.0。途中は0.6.x/0.7.xを使い、機能追加を含めてもよい。
1.0の最終対応範囲は需要調査後にユーザーが決定し、その合意範囲の実装・検証・制約説明と必要な最終実機確認・公開判断を経る。
0.8.0を自動的に1.0としない。P2/P3の高度な残件を0.7/0.8の出荷条件へ戻さず、提供するP0/P1動作の不具合は残件へ追い出さない。

## minorごとの必須文書更新

全minorで[文書・出荷gate](ci-boundaries.md#マイナー版の文書・出荷gate)を行う。
README、CHANGELOG、互換性、追加/更新/復旧手順、状態一覧、台帳、優先実装と現在の計画、全guides等の現在文章を読み直す。
実装済みを未実装と書いた説明、過去のCI待機、現在版と一致しない手順・制限・公開範囲を残さない。
日付変更だけでは不足。既に正しい文章は理由付きで維持し、各pathの確認結果とhashを候補の検証記録へ残す。

候補固定前には「公開候補VERSION」「その時点の最新公開版PREVIOUS」を明確に区別して全文章を同期する。
出荷tagに入る文書が古い版を無条件に「現在」と呼ぶ状態を残さない。履歴はsource/時点付きで保持する。
公開後はmainのREADME/状態一覧/CHANGELOG/検証記録を公開済みへ更新し、公開状態に関係する文章を再確認する。
既存tagや過去release notesを書き換えず、公開後の確認commitを明示する。

```powershell
python Tools/check-delivery.py --list-docs 0.7.0
python Tools/check-delivery.py --report PATH_TO_REVIEWED_REPORT --stage release --release 0.7.0
```

0.8.0では版とP1-Bのreportへ置き換える。toolの構造検査に加えて、担当は文章の正確さと実証ログを確認する。

## 0.7.0完了時の調査結果確認

ユーザーが需要調査を別途実施中（2026-09-12）。0.7.0完了時までに結果が文書/計画へ反映されているか確認する。
未反映ならその時点で結果の提供をユーザーへ依頼し、依頼日と反映待ちを記録する。今すぐ再依頼しない。
この確認を行ったことは1.0境界の決定や、調査結果の内容を承認したこととは別である。

## 候補の準備と検証

1. 変更内容、対象範囲、既知の不具合、再検証が必要な項目を整理し、CHANGELOGと版別release notesへ記録する。
2. 本体/Widgetのshort versionとbuild番号、CIの期待値を揃え、commit/pushする。配布用候補はCI成功を確認したimmutable commitへ固定する。
3. 共有・Module tests、単独Feature/生成host、App Intents metadata、本体/Widget、IPAを検証する。UIは変更の影響範囲を含む試験を行い、必要なら通常hostと生成hostを分割してjob上限内に収める。限定filterを全回帰成功とは記載しない。
4. 直前の検証済みsourceから版番号・文書・版検査値だけを変更した場合、差分を確認したうえでそのUI証拠を参照できる。候補のビルド/IPA検査は省略しない。参照元source/runと候補source/runを分けて記録する。
5. 新しい実機確認が必要な挙動があれば、複数項目をまとめて依頼する。過去の実機成功を別sourceの実機成功へ読み替えない。Simulatorだけの既知の失敗も、その範囲・実機証拠・未解明部分を明示する。
6. run.headShaを確認して通常構成のIPAを取得する。全ZIP entryの展開/CRC、bundle ID、版番号、App Group/署名構造、CI fixtureの混入がないことを確認する。source・run・SHA-256を検証記録とrelease notesへ残す。

publication boundaryは追跡ファイルの鍵・証明書・provisioning・pairing材料、SDK archive、IPA等を検査する。ignoredの個人Featureや実データを出荷物へ含めない。通常IPAはCounter/Reminder、Recordsは参照ソース。CI専用Featureを含む確認用構成と区別する。

## 公開と確認

検証済みcommitに新規tagを作り、同じIPAとnotesを公開する。tag形式は既存の`0.1.0`/`0.2.0`に合わせる。1.0には上記の利用者判断も必要。

```powershell
git tag -a VERSION VERIFIED_COMMIT -m "JibunKit VERSION"
git push origin VERSION
gh release create VERSION PATH_TO_IPA --repo y-aplus/JibunKit --verify-tag --title "JibunKit VERSION" --notes-file PATH_TO_NOTES
```

公開前にVERSION/VERIFIED_COMMIT/各PATHを具体値へ置き換える。既存tagを移動せず、既存assetを差し替えない。公開後はtagのcommit、公開assetのdigest、releaseページ/IPA取得を確認する。README・CHANGELOG・検証記録の公開状態を更新する。ユーザーにはIPAの直接リンクも示し、外側のActions artifact ZIPを必須にしない。

0.6.0の公開物・参照証拠は[公開記録](verification/2026-09-12-0.6-release.md)で管理する。過去の[0.3.0公開記録](verification/2026-09-10-0.3-release.md)も保持する。
