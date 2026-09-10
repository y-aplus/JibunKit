# D20 URL宣言の合成

状態: 以下のCI検証済み。D20の他の構造化配列・署名条件等は未完。

D12の独自URL受信を接続した際、Feature一つのscheme追加でも`CFBundleURLTypes`配列全体のresolutionが必要だった。hostとFeatureのnative URL宣言を集め、異なるURL typeの追加に手書きの全体配列を不要にする。

## 契約

宣言辞書はname/role/icon/任意metadata/元のscheme配列を保持する。host、Feature登録の順に集め、完全一致だけを重複除去する。名前なしも許可する。同じ`CFBundleURLName`に異値がある場合は誤った名称・role等の選択を避けるため衝突とし、既存のkey全体resolutionで明示解決できる。同schemeを別名のURL typeで宣言することは許可し、Feature受信先の曖昧性はD12で扱う。既存resolutionは最終native値をそのまま採用する。

対象はこの標準keyのみ。document types/UTI等へ同じ意味付けを推測適用しない。設定合成はOSへの登録可能性や他アプリとのschemeの一意性を保証しない。

## 検証計画

- native Tuist helperでhost/A/Bの辞書保持、完全一致重複除去、名前なし、同名異値拒否、明示解決、不正な配列型、B除去後のA/host保持、別target非混入を確認。
- native appのビルド済みInfo.plistからhost/A/Bのscheme/name/role/iconを読み戻し、Widgetには混入していないことを確認。
- 先行URL routing fixtureの手書きresolutionを外し、自動合成だけで独自scheme冷/温起動と他ownerの画面保持が成立することをiOSで再検証。通常のjibunkitリンク回帰も実施。

Apple [CFBundleURLTypes](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes)、[CFBundleURLName](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes/cfbundleurlname)、[CFBundleTypeRole](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleurltypes/cfbundletyperole)を参照。型や各keyの意味を根拠とし、同名衝突拒否はJibunKit側の明示的な合成規則であってOSのエラー規則と同一とは扱わない。

## CI証拠

[34537911487](https://github.com/y-aplus/JibunKit/actions/runs/34537911487)、source `96c095fbe259dd7d48ef0000656f8248707a839a`、Xcode 26.6で成功。

- native Tuist helperの合成・拒否試験が成功。ビルド済みappのhost/A/B URL宣言の辞書全体とWidgetへの非混入を照合。
- 手書きresolutionを外した隔離hostでも、独自URL冷/温起動・他Feature画面保持が53.956秒で成功。通常jibunkitリンクの回帰も23.566秒で成功。
- 共有159試験、独立package/生成Feature/通常app・Widget/IPAの検証は成功。
- Records UI stepには既知のQuick Look expected failureが残る。通常hostの全UI suiteとFiles round tripは今回のfilter対象外であり、成功範囲に加えない。
