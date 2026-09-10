# D20 Featureのplist/entitlements合成

状態: 実装済み、CI待ち。

Feature要求をTuist標準のProjectDescriptionHelpersでnative `Plist.Value`へ合成する。通常appとWidgetがそれぞれhost設定・Feature要求・明示resolutionを持ち、一般の異値衝突は失敗させる。意味が集合である限定keyだけ文字列配列を合成する。任意のSwiftアプリ設定を固定の能力一覧へ閉じ込めない。

旧`JibunKit.entitlements`/`JibunKitWidget.entitlements`の重複定義を削除し、Tuist生成entitlementsをCIのad-hoc署名へ渡す。通常targetのFeature要求は空で、現行App Group/version/URL/Widget設定を保持する。

## 検証経路

`Tools/verify-feature-build-requirements.py`が、固定Tuist 4.207.0配布物の本物のProjectDescription frameworkへSwift 6でリンクし、合成/衝突/明示resolution/異常/target分離を検査する。独自のPlist.Valueの模倣はしない。

`feature_validation=true`ではさらに一時projectをTuistで生成し、カメラ用途説明の明示resolution、背景mode集合、scheduler識別子、App Group集合を含むnative appをXcodeでビルドする。ビルド済みInfo.plistと、実ad-hoc署名から読戻したentitlementsを検査する。一時probeは通常IPAに含めない。通常app/WidgetのビルドとIPA検査も別に実行する。

WindowsではPython構文/diffを確認する。Swift/Xcode実行はmacOS CIのみ。診断logは`Feature-build-requirement-diagnostics` artifactへ保存する。

source `e887a29`の[34510497056](https://github.com/y-aplus/JibunKit/actions/runs/34510497056)で検証中。生成hostは直近の通常保存操作/復元のUI試験、通常hostは検索/起動回帰を選択した。両selectorの存在とPython構文/diffの検査は成功。完了はgh run watchからcodex queueへ通知する。

## 未完の範囲

構造化配列の一般合成、InfoPlist.stringsの多言語合成、privacy manifest、target/extensionの自動組立て、依存/Registry/要求の一元登録、任意SDKのschema検証は未実装。実provisioningとSideStore再署名後のcapability利用可否、権限同意やBackgroundTasksの実行契約はこの生成/署名試験では検証しない。D20全体の完了にはしない。

設計根拠: Tuist公式[ProjectDescriptionHelpers](https://docs.tuist.dev/en/guides/features/projects/code-sharing)、使用バージョンの[Plist.Value](https://github.com/tuist/tuist/blob/4.207.0/cli/Sources/ProjectDescription/Plist.swift)、[entitlements生成](https://github.com/tuist/tuist/blob/4.207.0/cli/Sources/TuistGenerator/Mappers/GenerateEntitlementsProjectMapper.swift)。
