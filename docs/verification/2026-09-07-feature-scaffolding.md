# ミニアプリ雛形生成の実装・検証

## 選定理由と範囲

更新した原則に従い、個別アプリの完成を待たず「追加時に基盤内部を毎回調べ直さなくてよい」開発体験へ投資する。今回はFeatureの雛形生成と登録を対象とする。既存アプリの解析・自動変換や、保存・通知の自動推定は含めない。

- [x] Feature所有の安定ID・定義・Contextを受け取るRoot Viewを生成。
- [x] PackageとRegistryへ明示した挿入位置を使って登録。
- [x] dry-run、重複・衝突・登録位置の欠落時に書き込まない挙動を検証。
- [x] 追加手順と検出範囲を文書化。
- [x] CIで生成FeatureのSwiftテスト・iOSビルドと本体の回帰を検証。

ローカルではPython unittest 4件が成功。連続追加、文字列のquote／補間文字のescape、dry-runの無変更、既存ID・ローカルFeature保持、marker異常時の全体無変更を確認した。実際のSwift／SwiftUIコンパイルも以下のCIで成功した。

既存Zaiko Featureと専用テストはignoreしたローカルファイルのまま保持する。

## CI結果

[run 34107397713](https://github.com/y-aplus/JibunKit/actions/runs/34107397713)、source `fc6b0c8f45523456be553319f9700fe33d37869a`で全step成功。

- Pythonの生成テスト4件成功。
- 通常構成と生成Featureを追加した隔離checkoutで、それぞれFoundationテスト21件成功。
- 生成したNotes Featureを含むiOS Releaseビルド成功。
- 通常構成のiOS Releaseビルド、本体・Widget・App Intents metadata、署名・IPA整合性の検査成功。
- Simulator UIテスト2件（独立保存・再起動、通知配信・タップ遷移）成功。証拠artifactの保存も成功。

生成Featureは隔離checkoutだけに存在し、通常IPAには含まれない。これは雛形の生成・コンパイルと既存機能の回帰の証拠であり、複雑なFeature全般の対応保証や実機検証を示すものではない。検証後の変更は文書のみ。
