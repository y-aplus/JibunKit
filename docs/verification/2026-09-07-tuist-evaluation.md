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

- [ ] Tuist 4.207.0（公開releaseのSHA-256を固定）でapp・Widget・UI testsを生成。
- [ ] Swift PackageテストとiOSビルド。
- [ ] App Intents metadata・App Group・識別子・IPA検査。
- [ ] CounterExample単独起動・加算・再起動・本体保存先との独立。
- [ ] 本体保存・通知UIテスト。直前のxtool runでも通知待機失敗があるため、失敗時は移行原因と決めつけず証拠を比較する。
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
