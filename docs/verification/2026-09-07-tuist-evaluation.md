# Tuist / TMA移行検証（Issue #1）

検証ブランチ: `codex/tuist-evaluation`。mainへのマージ・正式採用は未実施。バックアップ画面開発は止め、開発基盤の責務を優先して見直す。

## 比較と方針

JibunKitはFeature登録・遷移・保存先・system surface・データ継続性を所有する。Xcode projectとtarget生成はTuistへ寄せ、汎用project管理を独自実装しない。TMAはFeatureの単独開発と依存注入の判断軸として取り込む。interface/testing/exampleを全Featureへ機械的に増やさない。

| 現行責務 | 検証経路 | 採用時の扱い |
| --- | --- | --- |
| xtoolのproject生成 | Tuist Project.swift | macOS標準経路から置換。WSL補助経路の要否は別途明記 |
| RubyによるUI test target後付け | TuistのuiTests targetとscheme | スクリプトとxcodeproj gemを削除可能 |
| App Intents metadataの手動コピー | App sourcesをapp targetで直接コンパイル | 標準生成でIPA内に配置されるか検証 |
| add-mini-app.pyのPackage/Registry加工 | 今回は呼び出さない | Tuistのtemplate利用とFeature登録を分けて再設計。まだ置換完了とはしない |
| Swiftロジックとテスト | 既存Package.swift | 維持。Featureをpublic library productとして公開 |
| 単独試用 | CounterExample app shell | 本体と同じCounterFeatureを利用し、Storeを注入。本体と別suite |
| IPAの識別子・署名・構成検査 | 既存CI検査 | 維持 |

Tuistを標準経路へ追加しただけでxtool/Rubyも実行する方式にはしない。検証ブランチのCIでは両者を実行しない。既存スクリプトの削除は採用評価後に行う。

## 初回検証

- [x] Tuist 4.207.0（公開releaseのSHA-256を固定）でapp・Widget・UI testsを生成。
- [x] Swift PackageテストとiOSビルド。
- [x] App Intents metadata・App Group・識別子・IPA検査。
- [x] CounterExample単独起動・加算・再起動・本体保存先との独立。
- [x] 本体保存・通知UIテスト。直前のxtool runでも通知待機失敗があるため、失敗時は移行原因と決めつけず証拠を比較する。
- [ ] 上書き更新・SideStore再署名・Widget／Shortcutsの実機確認。

まだFeatureのJibunKitCore依存や定義をadapterへ完全分離したわけではない。今回の単独shell成立と、将来のFeature独立性の完成を混同しない。基盤の採用判断は削減した処理と単独開発体験、既存動作・データ維持を合わせて行う。

## 一次資料

- [Tuist local package example](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_local_swift_package)
- [Tuist app / extension example](https://github.com/tuist/tuist/tree/main/examples/xcode/generated_ios_app_with_extensions)
- [TMA](https://docs.tuist.dev/en/guides/features/projects/tma-architecture)
- [Tuist 4.207.0](https://github.com/tuist/tuist/releases/tag/4.207.0)

Zaikoのローカルignoreファイルは変更しない。

## 初回結果と修正

[run 34115636765](https://github.com/y-aplus/JibunKit/actions/runs/34115636765)、source `55eb566`。Tuist生成、Foundation 32テスト、app・WidgetのiOS Releaseビルド成功。IPA検査で旧生成物パスを参照して停止した。

Tuistが生成した実際のproduct名は`JibunKit_App.app`と`JibunKitWidget_Extension.appex`。検査・梱包のパスと診断ログのprocess名を一致させる。bundle IDや保存キーは変更しない。App Intents抽出stepの実行は確認できたが、IPA内のmetadata検査はまだ通過していない。単独版とSimulatorも後続stepのため未実行。

## 2回目結果と単独版修正

[run 34115937620](https://github.com/y-aplus/JibunKit/actions/runs/34115937620)、source `cc7e397`。IPAのmetadata・識別子・署名・ZIP検査、単独版ビルドとインストール、本体保存・通知UIテストまで成功。単独版の加算後の値確認だけ失敗した。

単独shellでsuite名に自身のbundle IDを渡していた。[AppleのAPI契約](https://developer.apple.com/documentation/foundation/userdefaults/init(suitename:))はこれを禁止している。単独版はnilを指定してアプリ固有のstandard defaultsを使うよう修正する。JibunKit本体のApp Group経路は変更しない。UIテストで再起動後の保存と本体側の不変を再検証する。

## 最終CI結果と評価

[run 34116894041](https://github.com/y-aplus/JibunKit/actions/runs/34116894041)、source `140649eee23947f709bb9a22f27e686a59b020e0`、2026-09-07 11:43 UTCに全step成功。

- Foundation 32テスト成功。
- Tuist生成のappとWidgetをReleaseビルド。App Intents metadataは手動コピーなしでIPA検査を通過。
- 本体・Widgetのbundle ID、版、App Group entitlement、ad-hoc署名、IPAのZIP整合性の検査が成功。
- CounterExampleをSimulatorへ導入。単独加算・再起動後の保存・本体側の保存値が変わらないことをUIテストで確認。
- 本体の保存・再起動と通知配信・遷移も含め、UIテスト3件成功。

### 判断

Tuistをproject構成管理の標準にする方向を推奨する。今回の経路はxtool project生成、RubyによるUI target後加工、App Intents metadataの手動コピーを実行せず成立し、同じFeatureの単独実行も実証した。Issueの採用判断基準である「独自処理の削減」と「単独開発体験の改善」の両方に具体的な証拠が得られた。

ただし正式な移行完了ではない。次を残作業として分ける。

1. 追加手順の一本化。現在のadd-mini-app.pyはPackageとRegistryだけを更新し、Project.swiftのpackage product依存までは追加しないため、Tuist経路の追加コマンドとしてそのまま案内できない。Tuist templateで雛形生成を受け持ち、Package product・host登録の明示手順と組み合わせるかを実装・検証する。古いスクリプトの置換・削除もここで行う。
2. 採用時にRubyスクリプト・不要となる依存noticeとドキュメントを整理する。xtoolはWSL補助経路を残す場合だけ用途を限定し、macOSの主経路として併用しない。
3. Feature固有の定義・backup接続と純粋なFeature実装の境界を整理する。現在もJibunKitCoreへの依存は残る。単独shellが動いたことをadapter分離完了とはしない。
4. Tuist生成IPAの上書き更新、SideStore再署名、Widget・Shortcutsの実機確認。bundle ID・保存キーの不変とSimulator成功だけでは代替しない。

主な負担はTuistの版固定・追従と、Swift Package／Project.swift間のproduct宣言の対応管理である。Tuistの導入だけではこの二重管理は解消しない。構成のsource of truthをさらに増やす独自manifestは今回追加しない。

mainへのマージ、正式リリース、Issue完了扱いは行っていない。検証後の変更はこの文書のみ。
