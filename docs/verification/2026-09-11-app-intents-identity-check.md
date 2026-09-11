# App Intents統合時の定義保持検査

## 目的

CI 34557984363で実証した同名entity/queryのsilent collisionを、別Featureでも再利用できる
検査へ切り出す。`Tools/verify-app-intents-integration.py`は明示された単独native metadataと
統合native metadataを読み、Intent/entity/queryの識別子・型と参照の保持を確認する。
Appleのmetadataを生成・修正しない。命名や構造をSwiftソースの独自parserで推測しない。

コンパイラのswiftconstvaluesには失われる前のA/B両型が残っていたが、DerivedData全体の走査では
非統合targetや古い生成物を混ぜる恐れがある。今回は統合対象として明示したbaselineを使う。
依存targetの自動選択は実装していない。

## ローカル検証

実CI出力の`actions` / `entities` / `queries`節を、他節を省略する以外は変更せず
`Tools/tests/fixtures/app-intents-identities`へ保存した。元run/sourceは同directoryのREADMEに記録。

4試験が成功した（0.006秒）。衝突版のnative出力を拒否し、明示persistentIdentifier版の
8定義を受理する。同一baselineの二重指定は受理し、定義の欠落・他型への置換・別queryへの
参照変更・空baselineの偽成功を拒否する。CLIも修正版8定義を受理した。

比較する参照情報のうち`resolvableInputTypes`だけは、変更のないnative build間でも順序が
変動する既存Counter比較の証拠に基づきsortする。内容・重複は保持し、引数順等は変えない。

## CI接続

既存Package App Intentsの6target build後、明示したStandaloneA/B app直下のmetadataと
Combined app直下のmetadataを比較する。従来のentity/query全辞書比較、Shortcut比較、iOS
直接実行は削除しない。通常製品コードは変更せず、既存のpackage_intents_validation経路で確認する。
新しい接続のCI結果は待機中。OS Shortcutsからの解決・表示や実行をこの検査の成功とは混同しない。
