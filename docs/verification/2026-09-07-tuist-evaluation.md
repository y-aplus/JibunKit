# Tuist / TMA移行検証（Issue #1）

検証ブランチ: `codex/tuist-evaluation`。利用者の承認後、移行CIの成功を確認しmainへ取り込む。以下の初回評価・修正履歴は当時の状態を記録する。バックアップ画面開発は止め、開発基盤の責務を優先して見直す。

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

## 採用・移行作業

利用者がTuistへの移行を承認。検証ブランチで以下を実施し、CI成功後にmainへ取り込む。

- xtool.yml、旧Info.plist、Ruby後加工、Python生成スクリプトとその専用テストを削除。
- Tuist templateで独立したSwift Packageと単独appを生成。ホスト依存・Registryは明示的に登録する。CIの隔離checkoutで単独版とホスト組込みの両方をビルドする。
- Counter／ReminderのMiniAppDefinitionをIntegration targetへ分離。Store・Root Viewと単独shellの接続は維持。
- 現行ビルド・追加・更新手順とnoticeを更新。過去の検証記録は当時の経路として保持。

本体bundle ID、App Group、保存キーは変更しない。移行後の実機確認は引き続き未実施であり、今回のmain統合は正式Release公開を含まない。

移行CI [34125388232](https://github.com/y-aplus/JibunKit/actions/runs/34125388232)はPackage.swiftの編集ミスでmanifestコンパイルに失敗。Integration targetの定義をproductのtarget名配列にも挿入していた2か所を修正した。template・iOS検証へ進む前の失敗である。

## 移行完了時の検証

[run 34125611924](https://github.com/y-aplus/JibunKit/actions/runs/34125611924)、source `03b37657d8b6ad05898269fc4303bab7f9c9dc2a`で全step成功。

- Foundationテスト32件成功。
- Tuist標準templateから生成した独立Featureの単独appと、ホストへの追加後のappを両方ビルドできた。
- Integration分離後の本体・Widgetビルド、metadata・署名・IPA検査が成功。
- UIテスト3件（本体の保存・再起動、通知配信・遷移、単独Counterの加算・再起動・本体との独立）が成功。

Tuistを標準経路として採用し、旧生成処理を削除した状態をmainへ取り込む。実機でのTuist版への上書き更新・SideStore再署名・Widget／Shortcuts確認は残る。Issue #1はこれらの検証項目が未完了のため閉じない。正式Release公開も行わない。

生成templateはJibunKit非依存、既存Counter／Reminderは定義をIntegrationへ分けたが共通保存APIへの依存は維持する。任意のFeatureの完全独立性を一律に保証するものではない。検証後の変更は文書のみ。

## 2026-09-08 実機での簡易確認

利用者へ渡した対象は[run 34125611924のIPA artifact](https://github.com/y-aplus/JibunKit/actions/runs/34125611924/artifacts/10020042143)内の`JibunKit.ipa`（上記source、Zaikoなし）。利用者から、上書き後の保存値、Widget、ショートカット、通知、SideStore再署名について「軽く試した範囲では大丈夫そう」と報告を受けた。

これらは利用者による実機の簡易確認で問題が見つからなかったという証拠として扱う。今回の端末・OS版、個々の操作手順・回数は追加確認しておらず、長期利用や網羅的な回帰検証の完了は主張しない。上記の実機未実施という記述は、この報告前の状態である。
