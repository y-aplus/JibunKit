# Swift Packageの同名AppEntity/query比較

## 目的とnative基準

D27の残件として、独立した二つのSwift Packageに同名の`Entry` / `EntryQuery`を置く。
同じローカルID `shared-id`を持つ別データが、統合によって別Featureへ解決されないかを調べる。
App Intent本体はFeatureごとに異なる名前とし、今回はentity/query名の競合を切り分ける。

Appleの[AppEntity](https://developer.apple.com/documentation/appintents/appentity)と
[EntityStringQuery](https://developer.apple.com/documentation/appintents/entitystringquery)に従い、
標準のdefaultQuery、ID解決、文字列検索、候補、表示用property、entity型のIntent引数を使う。
独自entity registryやIDの変換機構を先に追加しない。

## 比較内容

既存のPackage App Intents fixtureとCI経路を拡張し、単独A・単独B・統合A+Bをbuildする。
app直下のnative metadataで、entity/query identifierが独立baseline同士で衝突しないこと、
統合後も両方の辞書が残ること、entity引数を受けるIntentの型・引数・戻り値・modeの保持を検査する。
差分がある場合はactual JSON artifactとfield差分を保存して判断し、条件を機械的に緩めない。

iOSの直接実行試験では、同じIDのA/Bを各defaultQueryで解決し、他Feature専用IDと不明IDを除外する。
検索・候補の所有範囲、A編集後に古いentity snapshotから最新データを読む動作、A削除後にBへ
fallbackしない動作、Bの内容と件数の保持を確認する。保存はFeatureごとのUserDefaults suiteを使う。

通常製品RegistryやCounterの公開Intent型は変更しない。従来のPackage Shortcut比較・寄与削除・
Counter metadata互換性はそのまま実行する。

## 証拠の範囲

下記CIでnative metadataとiOS直接実行を確認した。ローカルWindowsではSwift/iOS実行を検証していない。
Swiftから直接query/performを呼ぶ試験はOS Shortcutsの選択UI・保存済みentity解決・Siri配送の
実行証拠ではない。native metadataの登録と直接実行をそれぞれ記録する。
同名Intent型、OS側の候補選択、Widget/Controlへの接続は今回の比較範囲に含めない。

## デフォルト識別子の衝突を確認

[34557984363](https://github.com/y-aplus/JibunKit/actions/runs/34557984363)、source
`11330b51519c8c6983274aadd5329ae4d4a7ef3c` は6つのnative app buildとIntent辞書比較まで成功し、
entity identifierの衝突で失敗した。単独A/Bはそれぞれ`entities.Entry`と`queries.EntryQuery`を持つ。
統合appではentityが`IntentFeatureB.Entry`、queryが`IntentFeatureA.EntryQuery`の一件ずつになり、
A/B両Intentのentity引数は同じ`Entry`を参照していた。単なる比較ツールの順序差ではなく、
app metadataから片方の定義が失われた。Swift実行試験には未到達。

Appleの公開[PersistentlyIdentifiable](https://developer.apple.com/documentation/appintents/persistentlyidentifiable)
と[persistentIdentifier](https://developer.apple.com/documentation/appintents/persistentlyidentifiable/persistentidentifier)
に従い、entityとqueryへそれぞれFeature所有の安定した文字列を明示して再比較する。
Swiftの`Entry`/`EntryQuery`型名とレコードの`shared-id`は変更しない。デフォルトの名前衝突を
JibunKit固有の不変制約とは扱わず、標準の識別子指定で補えるかを検証する。通常Counterの既存識別子は変更しない。

## 明示した永続識別子で成功

[34558958859](https://github.com/y-aplus/JibunKit/actions/runs/34558958859)、source
`635680cc3e3a0afd73efa8f6479ce3b4d4bca06f` が成功した。A/Bのentityはそれぞれ
`com.jibunkit.intent-fixture.a.entry` / `com.jibunkit.intent-fixture.b.entry`、queryは各`.entry-query`。
単独A/Bのentity/query辞書全体が統合appにもそのまま残り、entity引数の参照も各ownerを保持した。
queryの`fullyQualifiedIdentifier`とentityの`defaultQueryIdentifier`はnativeのモジュール付き型名を維持している。

同名entity/queryのiOS直接実行は0.036秒、従来のIntent所有Store実行は0.033秒で成功。
共有186件は既知Keychain2件skip、失敗0。通常app/Widget/IPAとCounter互換性、独立Counter、
通常検索回帰（37.272秒）、従来のShortcut合成・同一DerivedDataでのA寄与削除/B保持も通過した。

対処は標準`persistentIdentifier`の明示で足り、entity型名やレコードIDの一律変更、独自query dispatcherは不要だった。
保存済みShortcutの互換性があるため、公開済みの永続識別子を統合のたびに生成し直す方針にはしない。
同名entity/queryは今回の方法で検証済みだが、OS Shortcuts選択UIや同名Intent型を検証済みに広げない。
