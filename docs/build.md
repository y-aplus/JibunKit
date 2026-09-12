# ビルドと検証

開発中のCIは[事前に固定した大きな境界](ci-boundaries.md)で実行する。小commitや担当者の提出ごとに起動しない。以下の入力例は実行方法であり、全変更への一律実行指示ではない。

標準のiOSビルドはTuist 4.207.0とXcode 26.6を使う。WindowsからはGitHub Actionsを実行でき、Mac購入は前提にしない。SwiftのあるmacOS／Linux／WSLでは`swift test`でFoundationロジックを確認できる。xtoolによるIPA生成経路は廃止した。

## 構成の所有場所

- `Package.swift`: 共通ロジック・Feature・Integrationのlibrary productsとテスト。
- `Project.swift`: app・Widget・UI tests・CounterExample、Info.plist値、iOS build settings。
- 本体とWidgetのentitlements: App Groupの宣言。
- `Tuist/Templates/feature`: 独立Featureと単独appの標準雛形。

生成されるxcodeproj・workspace・Derivedは編集・commitしない。旧Info.plistとxtool.ymlは削除済み。

## macOSで実行

Tuistの版をCIと揃え、Xcode 26.6を選択する。

```bash
swift test
tuist generate --no-open
xcodebuild build -workspace JibunKit.xcworkspace -scheme JibunKit-App -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

単独カウンターは`CounterExample` schemeで起動できる。本体のApp Groupではなく単独appのstandard defaultsを使う。

## WindowsからIPAを生成

```bash
gh workflow run build-ios.yml --ref YOUR_BRANCH -f simulator_tests=true -f feature_validation=true
```

workflowは固定SHA-256でTuistを導入し、Swiftテスト、通常app／Widgetビルド、App Intents metadata、識別子・版・App Group・ad-hoc署名・IPAの整合性を検査する。`JibunKit-ad-hoc` artifactからIPAを取得する。SideStoreで最終署名して導入する。templateの検証用Notesは隔離checkoutだけに存在する。

上記は通常回帰と生成Feature検証の指定であり、個別のnative比較をすべて有効にする指定ではない。入力省略時は両フラグがfalseで、共有・Moduleテストと通常IPAの検査を実行する。`feature_validation=true`でRecords単独、Tuist templateの生成・単独ビルド・ホスト組込みを追加する。

`simulator_tests=true`ではバックアップの選択復元・Files往復、本体の保存・通知と、単独Counterの加算・再起動・保存先分離をUIで検証する。両フラグがtrueなら生成Featureの単独起動・ホスト共存とRecordsの編集・添付も検証する。UI targetはTuistが生成する。Rubyによる後加工やmetadata手動コピーは行わない。結果・画面・診断ログは`JibunKit-simulator-evidence` artifactへ保存する。

エージェントによる長時間CIの待機は、モデルを動かさないOS側のバックグラウンド監視と、完了時に一度だけ送る同じ会話への`codex queue`で行う。`gh run watch --interval`やモデルによる定期確認は使わない。具体的なローカル監視設定はリポジトリへ同梱せず、[並列運用](parallel-implementation.md)のCI前レビューと完了通知の契約に従う。

PackageのIntents/Widget/resources、background/Web認証等のnative比較はworkflowの対応inputを明示する。`package_sdk_aliases_only=true`は通常IPA jobを省略し、`simulator_tests=false`ならmacOSの4比較、`true`ならSDK iOS hostの1比較を実行する。検証範囲はrunのinputs・実際に成功したstep・記録を正とする。

## 検証の境界

ビルド・Simulator成功は実機の上書き更新、SideStore再署名、Widget・Shortcutsの保証ではない。0.6.0の出荷検証は[公開記録](verification/2026-09-12-0.6-release.md)、公開後mainの追加は[現在状態](status.md)を参照する。Tuist移行時の記録は当時のsourceの履歴である。

## UI失敗の限定再現

診断時は`-f simulator_tests=true -f focused_ui_validation=true -f ui_test_filter=MigrationUITests/MigrationUITests/testNotificationDeliveryAndRouting`のように、単一test methodのXcode test identifierを指定できる。このfocused経路はpublication boundary、固定Xcode/Tuist、workspace生成、Simulator準備、指定UIテストと診断artifactだけを実行する。通常のSwift/Moduleテスト、Releaseビルド、IPA検査、Files往復は省略し、CounterExampleまたはBackupHarnessも指定テストが使う場合だけ準備する。

focused時の`ui_test_filter`には`UITests`配下に実在する`MigrationUITests/<TestClass>/test<TestMethod>`を一件指定する。形式とsource上の存在をSimulator起動前に検査し、実行後もXCTest logでその一件の成功を検査する。`simulator_tests=true`が必須で、`feature_validation=true`または`feature_ui_test_filter`との併用は入力エラーになる。`focused_ui_validation=false`の既存経路では、`ui_test_filter`と`feature_validation`の併用を含む従来動作を維持する。通常の全検証ではfilterを空に戻す。focused成功は指定した一件の証拠であり、Swift/Moduleテスト、通常IPA、全Simulator回帰、生成Feature/Records検証の成功として扱わない。ログのみ先に読む場合はSimulator-text-diagnostics artifactを取得できる。
