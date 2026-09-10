# D27 Package App Intents

状態: native比較fixture実装済み、CI未確認。

現在のCounter intentはapp target内にある。Feature側のSwift Packageでintentを定義し、Apple標準`AppIntentsPackage.includedPackages`でhostへ接続する経路を検証する。既存Counter intentの型・識別子・保存キーは変更しない。

## 比較構成

`Tests/PackageAppIntents`の二つのSwift Packageが、それぞれ公開AppIntentとAppIntentsPackageを定義する。同じ`amount`引数と`value`保存キーを持ち、保存domainはowner別にする。単独A、単独B、統合A+Bのnative appをTuist/Xcodeでビルドする。hostにはpackage登録と二つのApp Shortcutの宣言を置き、intent本体をhostへコピーしない。

`Tools/verify-package-app-intents.py`は各ビルド済みbundleのnative `extract.actionsdata`を読み、単独時と統合後の識別子・型名・title・引数・返り値・実行modeを照合する。統合時の二つのShortcut参照、単独appに他Featureが混入しないことも検証する。さらにiOSのhost付きXCTestで各intentの`perform()`と返り値、他ownerの保存値保持を確認する。

これはShortcutsアプリからのOS実行、Siri、Widget/Control/extensionへの接続、AppEntityのquery、同じ型名同士の衝突、複数のAppShortcutsProviderの合成の証拠ではない。fixtureはFeature接頭辞付きの異なるintent型名と、hostに一つのShortcutsProviderを使う。

CIでは`simulator_tests=true, package_intents_validation=true`で専用stepを選択できる。無関係な生成Feature/Records UIは`feature_validation=false`で省略可能。通常配布IPAへfixtureやprobeを混ぜない。失敗時もnative metadata・実行log・xcresultを`Package-App-Intents-diagnostics`へ保存する。

Apple一次資料: [AppIntentsPackage](https://developer.apple.com/documentation/appintents/appintentspackage)、[includedPackages](https://developer.apple.com/documentation/appintents/appintentspackage/includedpackages)、[App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)。標準package登録を再実装する独自generatorは作らない。
