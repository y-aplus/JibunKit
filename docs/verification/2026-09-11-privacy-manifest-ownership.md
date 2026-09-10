# D20 Feature privacy manifest ownership verification

Updated: 2026-09-11

## Scope

隔離fixture A/Bが異なる`PrivacyInfo.xcprivacy`を各Swift package resourceとして所有する。通常配布アプリへ架空申告は追加しない。独自manifest合成frameworkは作らない。

Appleはprivacy manifestをapp/third-party SDK targetのresourceへ追加し、Swift packageでは明示resource宣言するよう定める。Xcodeはappとlinked third-party SDKのmanifestからprivacy reportを集約する。

- [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)

## Native checks

`Tools/verify-privacy-manifest-ownership.py`はA/Bを個別に`swift build`し、各resource bundleのmanifestをplistとして読む。次にTuist hostを二構成でclean buildする。

- A+B構成: app直下のSwiftPM resource bundlesにA/B、Widgetに直接依存するBを確認。
- B-only構成: 依存を外し別DerivedDataへ新規buildする。appからA bundleだけが消え、app/WidgetのB manifestが内容・bytesとも維持されることを確認する。これはincremental build directoryからstale resourceを清掃する試験ではない。

独立buildで読んだA/B辞書を基準に、A+B appのA/B、WidgetのB、B-only app/WidgetのBを個別に照合する。

これはnative bundle内の存在・配置・内容・所有者別除去の証拠である。Organizer privacy report生成、App Storeの申告やmanifest内容の実態適合性は別途確認が必要であり、本試験の成功から推定しない。

Run 34529562304, source `8368e7ebd8c13e3fe207cd54422c2b5c33b6ac3f`, は独立A/BのSwiftPM buildとmanifest読取りに成功した後、一時fixtureにTuist root markerがなく統合project生成前に停止した。空の`Tuist/` markerを作成して再検証する。

Run 34530020690, source `1c9eb0ef0e98491ccbc97009ebd7c1d5b3efe026`, はA+BとB-onlyのbuild自体には成功したが、同一rootへの2回目の`tuist generate`が以前のA依存を生成済みprojectに残すことを検出した。B-only検証を別DerivedDataだけでなく別のclean Tuist project rootでも生成するよう分離して再検証する。
