# 公開・release手順

更新日: 2026-09-04

0.1は、F1〜F7とO1〜O4を満たすsource、tag、変更履歴、IPAを対応付け、リポジトリ公開と同時にreleaseする。それまではリポジトリをprivateのまま保つ。公開切替やrelease作成は、利用者の明示的な最終確認を受けてから行う。

## 現在の公開先

- repository: `y-aplus/AppbaseIOS`
- default branch: `main`
- visibility: private
- license: MIT

状態はGitHub CLIで確認できる。

```powershell
gh repo view y-aplus/AppbaseIOS --json nameWithOwner,visibility,defaultBranchRef,url
```

## 公開前チェック

1. `docs/verification/0.1.md`でF1〜F7が合格し、O1〜O4の公開前に実施できる項目が揃っていることを確認する。
2. `main`がcleanで、release対象の変更がすべてcommitされ、`origin/main`と一致していることを確認する。
3. `swift test`を実行する。
4. release対象commitから`.github/workflows/build-ios.yml`を手動実行する。workflowのpublication boundary、Xcode build、App Intents metadata、本体・Widget、entitlements、署名構造、IPA整合性がすべて合格したrunだけを使う。
5. runの対象commitとrelease対象commitが一致することを確認し、取得したIPAをSideStoreで上書き導入する。
6. 同じ版のIPAでF1〜F6を再確認し、端末、OS、SideStore版、操作結果を検証記録へ追記する。
7. IPAを展開し、credential、個人の署名材料、provisioning profile、pairing file、実データ、Apple SDK、不要な生成物が含まれないことを確認する。
8. `CHANGELOG.md`の`0.1.0`の日付と`release-notes-0.1.0.md`が公開内容に一致することを確認する。

workflowのpublication boundaryは、追跡済みの`.env`、鍵・証明書・provisioning・pairing関連file、Xcode/SDK archive、IPA/xcarchiveと、代表的なprivate key・GitHub token形式を検査する。このチェックは万能なsecret scannerではないため、差分と最終IPAの内容確認を省略しない。

## tag、公開、release

公開前チェックがすべて合格し、利用者が公開を承認した後にだけ実行する。

```powershell
git tag -a 0.1.0 -m "AppbaseIOS 0.1.0"
git push origin 0.1.0
gh repo edit y-aplus/AppbaseIOS --visibility public --accept-visibility-change-consequences
gh release create 0.1.0 .\actions-run-RUN_ID\AppbaseIOS.ipa --verify-tag --title "AppbaseIOS 0.1.0" --notes-file .\release-notes-0.1.0.md
```

`release-notes-0.1.0.md`は公開前に作成し、確認済み環境、導入方法、既知の制限、変更履歴へのlinkを含める。IPAの取得元を曖昧にせず、Actionsの一時artifactをrelease成果物として参照し続けない。

## 公開後の確認

- repositoryがpublicで、default branchが`main`、LICENSEと第三者noticeが表示される。
- tag `0.1.0`が意図したrelease commitを指す。
- releaseのIPA、release notes、`CHANGELOG.md`、`docs/verification/0.1.md`が同じ版を説明している。
- GitHubのprivate vulnerability reportingを有効にし、`SECURITY.md`の報告入口が利用できる。
- 公開ページとrelease assetにcredential、署名・pairing材料、端末固有ID、実データ、Apple SDKがない。

どれかが成立しない場合はO1またはO4を完了にせず、問題を解消して対応関係を再確認する。
