# D20 localized InfoPlist.strings verification

Updated: 2026-09-11

## Scope

`FeatureBuildRequirement`のFeature/locale/key別用途説明をtarget単位で合成し、Apple標準の`<locale>.lproj/InfoPlist.strings`としてiOS app/widget bundleへ組み込む。Feature UI全体の翻訳、実権限grant、privacy manifestは対象外。

Appleは用途説明を含む人向けInfo.plist値のlocalizeを推奨し、各言語の`InfoPlist.strings`へkey/valueを置く。`Bundle.localizedInfoDictionary`は現在の優先localizationに対応する辞書を返す。

- [Managing your app's information property list](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list)
- [About Information Property List Files](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AboutInformationPropertyListFiles.html)
- [Bundle.localizedInfoDictionary](https://developer.apple.com/documentation/foundation/bundle/localizedinfodictionary)

## Checks

native Tuist helper testは、ja/enの同値保持、異値衝突時のlocale/key/owner付き拒否、hostの明示resolution、余剰resolution/空locale/key拒否、app/widget分離を確認する。

build probeはappと埋込みwidget extensionを実際に生成・buildする。両bundleの`en.lproj`/`ja.lproj`を確認し、Foundation `Bundle`でlocalizationを指定して`InfoPlist.strings`をnative読戻しする。appでは解決済み`NSCameraUsageDescription`、widgetではtarget固有`CFBundleDisplayName`を比較する。Python辞書の合成結果だけでは成功扱いしない。

Run 34523984820, source `8445cebba4b773829c7d7fc65452273570c3ce32`, はhelper検査とTuist生成を通過したが、fixtureがresourceをTuist管理対象の`Derived/`へ書いたためgenerate後に入力fileが消え、Xcode buildで失敗した。生成先をTuistが清掃しない`GeneratedResources/`へ変更する。

Run 34524360773, source `0807926db0358daeea9c51514e9da3031a0a5128`, はapp/widget buildとlocalized resource組込みを通過した後、検証用macOS `Bundle.path`呼出しの`inDirectory`引数不足でcompileに失敗した。`nil`を明示してnative読戻しを再実行する。

Run 34524770105, source `8da7614a454547cff5a340de13e862a08e72fa5b`, は全工程success。native Tuist合成検査、app/widget build、両bundleのen/ja `InfoPlist.strings`に対するFoundation `Bundle`読戻し、通常app/IPA buildが成功した。最終checkpointでは再生成前の限定清掃と、削除済みfr localeがbundleへ残らない検査を追加する。

Run 34525725652, source `ad879e0a5b74782fb15e68df04972e9dd5e622aa`, は最終checkpointの全工程success。`Native Tuist requirement merge/validation checks passed`、`Native Bundle readback passed for app/widget en+ja; stale fr localization absent`を記録し、独立Feature packages、native Feature template、通常Xcode build、ad-hoc署名、IPAも通過した。これにより合成結果だけでなく、生成された二つのiOS bundle内の言語resourceとnative読戻しを証明した。

通常`Project.swift`もapp/widgetのhost localized値を`compose`へ渡し、ignore済み生成専用`GeneratedFeatureResources/App`・`Widget`へ書出して各targetのresourcesへ接続する。製品検証stepはbuild後のapp/widget bundleからen/jaの`CFBundleDisplayName`を`plutil`で読戻し、target別期待値とapp-only keyの非流入を確認してからIPAを作る。host localized値はFeature要求と同じ衝突・resolution規則へ含む。

Run 34527122584, source `4f1bd674e276b9b53db420c4e7dd8b20bf05e12c`, は最新main統合後の全工程success。fixtureのnative app/widget en+ja読戻し・stale fr排除に加え、通常製品appのen/ja `JibunKit`、widgetのen `JibunKit Widget`・ja `JibunKitウィジェット`をbuild済みbundleから読戻して一致した。app-only keyのwidget非流入、ad-hoc署名、IPA作成も同じstepで成功した。
