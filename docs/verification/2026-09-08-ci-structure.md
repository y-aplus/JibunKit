# Issue #2: 本体構成とCIの責務

[Issue #2](https://github.com/y-aplus/JibunKit/issues/2)をv1.0の残作業として扱う。今回の変更はCI結果待ち。

## Packageとappの定義

Project.swiftは本体app・Widget・UI testの唯一の定義元とする。ルートPackageのJibunKit/JibunKitWidget library productとtargetは、Projectや他Packageから参照されていないことを検索で確認して削除した。Core/Feature/Integration/BackupとそのテストはPackageに残す。アプリのSwiftUIコンパイルとApp Intents metadataは従来通りXcodeビルドで検証する。

## 独立Packageのテスト

通常CIはTools/test-module-packages.pyでModules直下の各Package.swiftを調べる。swift package dump-packageのtest targetがあればswift testを実行し、無ければその旨をログへ記録する。新Featureにテスト追加を強制しない。パッケージの読込みやテスト失敗はCI失敗として伝播する。

iOS専用テストがあるFeatureはModules/<Name>/ci-test.shを用意する。このスクリプトは当該Packageを作業ディレクトリとしてbashで実行され、Featureの全テストを実行する責任を持つ。必要なSimulator準備・Tuist generate・xcodebuild testと、併存するFoundationテストを明示する。標準経路はmacOSのswift testであり、iOSテストを自動判別して黙って省略しない。ci-test.shはテスト不要の印ではない。

## 実行モード

- 通常: 共通・全独立Packageのテスト、本体/Widgetビルド、metadata、IPA検証。
- simulator_tests=true: 通常に加えて既存の本体UIとバックアップ・Files回帰。
- feature_validation=true: 独立Recordsビルド、生成templateのPackageテスト発見・単独ビルド・ホスト組込みビルド。
- 両方true: 上記すべてとRecords/生成Featureの独立起動・ホスト共存UI。

template・Package/Project・Integration・ナビゲーション・共有保存先など、Feature追加や組込みへ影響する変更ではfeature_validation=trueを指定する。出荷候補も両方trueで検証する。差分を推測する独自影響解析は追加しない。通常モードが成功しただけでは重い検証の成功とは扱わない。

バックアップ画面の再検証run 34205814278は変更前のworkflow/sourceで継続中であり、その結果と今回の構成変更の検証結果を区別する。
