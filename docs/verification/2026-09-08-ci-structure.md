# Issue #2: 本体構成とCIの責務

[Issue #2](https://github.com/y-aplus/JibunKit/issues/2)の構成整理を実施。CI [34206702845](https://github.com/y-aplus/JibunKit/actions/runs/34206702845)、source `681d194b8afbd0be14cd6165e848c21843de8f43`で両入力trueの全検証が成功した。

通常の独立Package発見でRecordsFeatureTestsを実行し、隔離template検証では生成NotesにPackageテスト未定義と明示した上でRecordsテストも実行した。app/Widget library削除後の本体・Widget・App Intents metadata・IPA生成、独立起動、ホスト共存、バックアップUI、JSON Files往復がすべて成功。任意のiOS専用ci-test.shについては実行契約を提供した段階で、実Featureの採用例はまだない。通常モードとビルド成果物共有の時間測定は別run 34209642170で確認する。

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

## 待ち時間の短縮

run 34205814278ではIPAアップロードまで約5分、Simulator準備約3分28秒、Counterビルド約3分、Records単独テスト工程約13分46秒、生成Feature単独約1分39秒、生成Featureホスト約4分26秒だった（工程時間であり純粋なテスト実行時間ではない）。待ち時間の主要因はIPA生成後の検証である。

通常の画面修正はsimulator_tests=true / feature_validation=falseを使い、独立Feature検証を必要な変更・出荷時に限定する。今回さらに、同じworkspace・Debug・Simulator・署名設定のCounterExample、BackupHarness、本体UIテストのderivedDataPathをSimulatorDerivedDataへ統一する。順次実行を保ったまま共通依存の再ビルドを減らす。別checkoutや署名設定の異なる生成Featureホストの成果物は共有しない。短縮幅は新runの実績で確認し、現時点では保証しない。
