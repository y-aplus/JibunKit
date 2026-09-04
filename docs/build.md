# ビルド手順

更新日: 2026-09-04

AppbaseIOSは、Windows上のWSLで行う高速なローカル確認と、GitHub Actions上のXcodeで行うSideStore向けIPA生成を分ける。WSLのxtool 1.17.0だけではShortcuts登録に必要な公式App Intentsメタデータを生成できないため、ローカルIPAを実機導入用成果物として扱わない。

固定版と経路を選んだ理由、実測したrun、料金上の注意は[ビルド経路の判断記録](decisions/build-route.md)を参照する。

## 使用する構成

| 対象 | 固定値 |
| --- | --- |
| ローカル環境 | WSL 2、Ubuntu 24.04、Swift 6.3.3、xtool 1.17.0 |
| ローカルApple SDK | Xcode 26.6 Universal由来のDarwin Swift SDK |
| クラウド環境 | GitHub Actions `macos-26`、Xcode 26.6、xtool 1.17.0 |
| iOS deployment target | iOS 26.0 |
| app / Widget | `com.example.AppbaseIOS` / `com.example.AppbaseIOS.Widget` |
| App Group | `group.com.example.AppbaseIOS.shared` |
| 版 | 0.1.0、build 1 |

アプリの構成は`Package.swift`、`xtool.yml`、本体とWidgetのInfo.plist・entitlementsに置く。workflowや生成物を手作業で書き換えて設定差を吸収しない。

## WSLでテストする

SwiftとxtoolへPATHが通ったUbuntu 24.04上で、リポジトリ直下から実行する。

```bash
swift test
xtool dev build --ipa
unzip -t xtool/AppbaseIOS.ipa
sha256sum xtool/AppbaseIOS.ipa
```

`swift test`はカウンターの保存・並行加算・整数overflow、SideStore App Group解決、ミニアプリIDの衝突、カウンターとリマインダーの独立保存を検査する。現在は全11テストである。`xtool dev build --ipa`はiOS向け本体、リマインダー通知、Widgetをコンパイルし、`xtool/AppbaseIOS.ipa`を生成する。

このIPAで確認できるのは、iOS向けコンパイル、Widgetの組込み、IPAのZIP整合性までである。`Metadata.appintents/extract.actionsdata`がないため、Shortcutsを含むSideStore実機検証には使わない。

## GitHub ActionsでIPAを作る

`.github/workflows/build-ios.yml`は`workflow_dispatch`だけで起動する。pushやpull requestでは自動実行されない。実行対象のコミットを`origin/main`へpushした後、GitHub CLIで起動・監視・取得する。

```bash
git push origin main
gh workflow run build-ios.yml --ref main
gh run list --workflow build-ios.yml --limit 1 \
  --json databaseId,url,status,conclusion,headSha
gh run watch RUN_ID --exit-status
gh run download RUN_ID --name AppbaseIOS-ad-hoc --dir actions-run-RUN_ID
```

`RUN_ID`は`gh run list`が返す`databaseId`へ置き換える。複数のrunが近接している場合は、`headSha`が今回pushしたコミットと一致することを確認する。

workflowは次を順に検査し、どれかが失敗した場合はartifactをuploadしない。

- 追跡済みのcredential・署名・pairing・SDK・IPA候補がないこと。外部GitHub Actionは固定commitを使い、checkout credentialを保持しない。
- Xcode 26.6とxtool 1.17.0の版、およびxtool archiveのSHA-256。
- `swift test`の全テスト。
- `AppbaseIOS-App` schemeのRelease／実機向けXcodeビルド。
- Xcode公式processorが生成した非空の`Metadata.appintents/extract.actionsdata`。
- 本体とWidgetのarm64実行ファイル、bundle ID、0.1.0／build 1。
- 本体とWidgetの論理App Group、アドホック署名、IPAのZIP整合性。

成功時のartifact名は`AppbaseIOS-ad-hoc`、中身は`AppbaseIOS.ipa`、保持期間は7日である。これはSideStoreで再署名するための検証物であり、0.1のrelease成果物ではない。

工程4の確定runは[`33465093595`](https://github.com/y-aplus/AppbaseIOS/actions/runs/33465093595)、対象commitは`a3098ef`である。新しいクリーンな`macos-26` runner上で全10テスト、Xcode 26.6ビルド、公式App Intentsメタデータ、Widget、署名、IPA検査に合格した。同一IPAをSideStoreで上書き・署名更新し、F1〜F6を実機で確認した。

工程5の公開前確認runは[`33825680660`](https://github.com/y-aplus/AppbaseIOS/actions/runs/33825680660)である。固定commit参照のGitHub Actions、checkout credentialの非保持、publication boundaryを含む全stepがprivateの`main`から合格した。取得したIPAにも、禁止対象の鍵・証明書・provisioning・pairing・SDK fileと代表的なcredential形式がないことを別途確認した。このrun後の変更が文書だけでなく製品・workflowへ及ぶ場合は、工程6で新しいrunを使う。

## 認証情報と料金

workflowへApple Account、パスワード、2FA、証明書、provisioning profileを渡さない。GitHub CLIのtokenや端末情報もリポジトリへ保存しない。

公開境界チェックの対象と限界、およびrelease前に必要な追加確認は[公開・release手順](releasing.md)を参照する。

非公開リポジトリの標準runnerはGitHub Actionsの利用枠を消費し、契約状態によっては超過料金が発生する。必要な節目だけ手動実行し、現在の料金・残量はGitHubのBilling画面で確認する。公開を前倒しして利用料を避ける運用はしない。

## 証拠の残し方

採用判断には、コミットSHA、Actions run URL、job結果、IPAのbyte数とSHA-256、実機の機種・OS・SideStore版、実際の操作結果を[0.1検証記録](verification/0.1.md)へ残す。ローカルテスト、クラウド生成、SideStore導入、実機動作は別々の証拠として扱う。
