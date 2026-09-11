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

実装を用意しCI検証待ち。ローカルWindowsではSwift/iOS実行を検証していない。
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
