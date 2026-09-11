# 通常hostのFeature所有Shortcut接続

## 目的と変更

検証fixtureだけでなく、通常hostもFeature所有のShortcut定義を使う。Counterの既存AppShortcut式を`Sources/CounterIntegration/AppShortcuts.swift.fragment`へ移し、Project.swiftが有効な寄与を列挙して生成Providerをapp targetへ含める。Swift Packageはfragmentをコンパイル対象から除外する。

既存`AddCounterValueIntent`の実装・型・app moduleは移さない。生成Providerも従来の`JibunKitShortcuts`型名を使うため、既存Shortcutとの互換性を確認できる。Widgetと独立Counterのtargetには生成Providerを追加しない。生成ファイルはgitignore対象で、Tuist再生成時に作る。

## 互換性の基準

変更前の通常IPAは[34550748042](https://github.com/y-aplus/JibunKit/actions/runs/34550748042)、source `920a3d2a7e74b87a69e383f1e72a758fe75101f7`。そのapp直下`Metadata.appintents/extract.actionsdata`からprovider identity、actions、autoShortcutsを抽出し、`Tests/AppShortcuts/CounterBaseline.json`へ固定した。手書きの期待値で新実装をなぞったものではない。

通常IPA検査で`verify-host-shortcut-compatibility.py`を実行し、既存CounterのProvider名・Intent metadata全体・Shortcut辞書がこの基準と一致することを必須とする。将来追加される別Intentは拒否しない。既存Intentの意図的な仕様変更時は、基準を機械的に再作成せず互換性を判断する。

ローカルでは変更前metadataを受理し、Intentの型名を変えたmetadataを拒否することを確認。Swift/Tuist生成、通常iOS/Widget/IPA、二Feature合成比較、既存画面回帰はCI待ち。OS Shortcutsに以前から保存されたworkflowの実行互換性までをmetadataだけで実証したとはしない。

## 最初の通常host検証

[34552604139](https://github.com/y-aplus/JibunKit/actions/runs/34552604139)、source `6ce59a1cb2b3a2c36550a2a413862cb6d69999ee` はiOS build後の互換性検査で失敗。Provider名の一致は通過したが、AddCounterValueIntentの辞書一致が失敗した。Intent実装は変更していないものの、差分を取得できていないため無害とは判断しない。現在の検査は失敗時のactual metadataを保存していなかったため、JSON artifact保存とfield単位のdiff表示を追加する。比較条件は維持し、次の診断は共有試験/通常buildのみで、到達しないSimulatorを予約しない。

## 不一致の特定と比較方法

[34552915930](https://github.com/y-aplus/JibunKit/actions/runs/34552915930)、source `8d0a4f8c439d184a264e7e79fc557492dd979bae` のactual metadataを取得した。差分は`parameters[0].resolvableInputTypes`の順序だけで、基準のprimitive type identifier列`[7, 2, 0]`が`[0, 2, 7]`になっていた。その他のIntent辞書、Provider identity、Shortcut辞書は一致した。

合成前の独立したcontrol IPAも取得して比較した。34552157327では`[7, 2, 0]`、34551805751では`[2, 7, 0]`だった。両者のCounter Intent/手書きProviderソースは同一であり、この並びの変動は合成機構の導入に固有ではない。数値の意味を推測して除外せず、native入力型の各辞書全体を保持してこの配列だけsortして比較する。引数順・phrase順など他の配列は変更しない。重複も残すため型の欠落/追加は検出する。

比較ツールに、入力型の順序変更だけは通り、型の欠落/重複・Intent identity・戻り値・phrase・Providerの変更は落ちる回帰試験を追加した。取得済みactual metadataもローカルで再比較する。製品Swiftを追加変更せず、次のCIで通常IPA・単独/統合Shortcut・通常UI回帰を再検証する。
