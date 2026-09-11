# 同名AppIntent型と公開識別子

## 比較内容

D27の同名Intent型を、既存のentity/query比較fixtureで検証する。A/Bそれぞれの
`FeatureAReadEntryIntent` / `FeatureBReadEntryIntent`を同じSwift名`ReadEntryIntent`へ変え、
標準`persistentIdentifier`には変更前のnative metadataのidentifierを明示する。
レコードID、entity/queryの識別子、保存先、引数・戻り値は変えない。

単独A/Bと統合appのnative metadataで、二つの異なるモジュールの`ReadEntryIntent`が残り、
公開identifierが以前と同じ`FeatureAReadEntryIntent` / `FeatureBReadEntryIntent`であることを要求する。
既存の識別子・参照の比較ツール、entity/query全体比較、Shortcut合成/削除も同時に実行する。
iOS直接実行はそれぞれのmoduleで型を明示し、編集後の再取得・削除時の他owner非参照・B保持を確認する。

型の実装上の完全名は変更されるが、公開identifierを維持できるかを検証する単位である。
OS Shortcutsに保存されたworkflowの移行実行やSiriによる曖昧性解消は未検証として残す。
通常Counterの公開型や保存済みデータは変更しない。

## 状態

CI待ち。今回のrunは最近統合したgenerated hostのNow Playing fixtureを同時に実行し、
host launch fixtureとのworkflow統合もbuildで確認する。通常UIは検索に限定し、全件再実行とはしない。
