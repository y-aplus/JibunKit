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

CI結果は下記。今回のrunは最近統合したgenerated hostのNow Playing fixtureを同時に実行し、
host launch fixtureとのworkflow統合もbuildで確認する。通常UIは検索に限定し、全件再実行とはしない。

## CI結果

[34561579846](https://github.com/y-aplus/JibunKit/actions/runs/34561579846)、source
`0949dc7d9fa8024131bf12280679e4c9e7687089` が成功。単独A/Bと統合appの両方で
`IntentFeatureA.ReadEntryIntent` / `IntentFeatureB.ReadEntryIntent`が存在し、公開identifierは
それぞれ以前の`FeatureAReadEntryIntent` / `FeatureBReadEntryIntent`を保持した。
識別子・参照検査の8定義、entity/query全辞書比較、Shortcutの合成と寄与削除も通過。
同名query/Intentの所有データ操作0.017秒、従来のIntent実行0.013秒が成功した。

共有186件は既知Keychain2件skip/失敗0。通常app/Widget/IPAとCounter互換性、generated Feature
build、Now Playing比較（12.253秒）、通常検索回帰（27.432秒）も成功した。HostLaunchHookと
NowPlaying双方のfixtureが含まれるhostのbuildを確認したが、起動hook専用UI testはこのrunでは再実行していない。

同名型を一律禁止する必要はなく、Featureが所有する標準の安定識別子とmoduleで区別できた。
OS Shortcutsの保存済みworkflow移行・Siriによる選択の成功までは主張しない。
