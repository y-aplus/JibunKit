# 公開・release手順

更新日: 2026-09-09

現在の公開版は0.1.0、mainは1.0開発中。2026-09-09にGitHubでrepositoryがpublic、default branchがmainであることを確認した。1.0の完了条件は[完成計画](superpowers/plans/2026-09-08-jibunkit-1.0.md)のV1〜V6で管理する。公開済み0.1の検証は過去版の証拠として保持する。

## 出荷候補を準備する

1. 完成計画の実装・自動検証を終え、残る実機確認と既知の制限を具体的に整理する。限定UIテストの成功を全回帰成功として扱わない。
2. 版番号、CHANGELOG.md、release-notes-1.0.0.mdを出荷内容に合わせる。候補sourceをcommitし、origin/mainと一致することを確認する。
3. 候補commitからbuild-ios.ymlをsimulator_tests=true、feature_validation=true、ui_test_filter空で実行する。共有・Module tests、単独Feature・生成ホスト、通常app/Widget、App Intents metadata、IPAとUIの結果を確認する。期待失敗は理由・対象を明示し、成功した機能の証拠に数えない。
4. runのheadShaと候補commitが一致することを確認し、IPAを取得する。展開検査・署名構造・bundle ID・App Group・版番号を確認し、SHA-256を検証記録へ残す。
5. 同じIPAをSideStoreで上書き導入し、署名更新、既存保存値、Widget/Shortcuts/通知、選択復元をまとめて実機確認する。Recordsなど参照Featureを含む確認用構成は、通常配布物との差分とsourceを明示する。
6. 実機結果、対象commit、run URL、IPA hash、既知の制限を記録する。不具合を直してIPAが変われば、影響する項目を再確認する。
7. release notesとIPAを揃えた具体的な公開成果物について、利用者の最終承認を受ける。

publication boundaryは追跡ファイルの鍵・証明書・provisioning・pairing関連ファイル、SDK archive、生成IPAなどを検査する。最終差分と配布IPAの確認も行う。ignoredの個人Featureや実データを公開物へ含めない。

## 承認後に公開する

承認されたcommitをtagへ固定する。既存tagを移動せず、既存releaseのassetを無断で差し替えない。

```powershell
git tag -a 1.0.0 APPROVED_COMMIT -m "JibunKit 1.0.0"
git push origin 1.0.0
gh release create 1.0.0 .\actions-run-RUN_ID\JibunKit.ipa --repo y-aplus/JibunKit --verify-tag --title "JibunKit 1.0.0" --notes-file .\release-notes-1.0.0.md
```

APPROVED_COMMITとRUN_IDは確認した値に置き換える。repositoryのvisibility変更は不要。release notesには導入方法、確認環境、source/run/hash、互換性、既知の制限、変更履歴を含める。

## 公開後の確認

- tagが承認されたcommitを指し、公開されたIPAのSHA-256が検証済みファイルと一致する。
- release notes、CHANGELOG、検証記録が同じ版と成果物を説明している。
- releaseページからIPAを取得でき、LICENSEとSECURITY.mdの案内が参照できる。

配布まで確認してV6を完了する。
