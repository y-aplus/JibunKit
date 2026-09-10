# 公開・release手順

更新日: 2026-09-10。最新公開版はGitHub Releasesを正本とする。0.3.0を公開済み。1.0は[共存の完成基準](coexistence-boundaries.md)と[差分台帳](coexistence-ledger.md)で判断し、旧V1〜V6やサンプルだけの成功で完了としない。

## 版ごとの出荷判断

0.xは検証済みの機能のまとまりを公開する中間版。2026-09-10のユーザー依頼により、着実な開発を続けながら適切な区切りで0.xを公開する。1.0の未達を明記し、未対応・未調査を出荷済み機能へ数えない。既存release/tagの差し替えはしない。

1.0は完成基準の実装・検証・残存制約の説明を終え、必要な最終実機確認と利用者の公開判断を経る。0.xの公開をもって1.0の承認とは扱わない。

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

0.3.0の公開物・参照証拠は[公開記録](verification/2026-09-10-0.3-release.md)で管理する。
