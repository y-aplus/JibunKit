# ミニアプリ雛形生成の実装・検証

## 選定理由と範囲

更新した原則に従い、個別アプリの完成を待たず「追加時に基盤内部を毎回調べ直さなくてよい」開発体験へ投資する。今回はFeatureの雛形生成と登録を対象とする。既存アプリの解析・自動変換や、保存・通知の自動推定は含めない。

- [x] Feature所有の安定ID・定義・Contextを受け取るRoot Viewを生成。
- [x] PackageとRegistryへ明示した挿入位置を使って登録。
- [x] dry-run、重複・衝突・登録位置の欠落時に書き込まない挙動を検証。
- [x] 追加手順と検出範囲を文書化。
- [ ] CIで生成FeatureのSwiftテスト・iOSビルドと本体の回帰を検証。

ローカルではPython unittest 4件が成功。連続追加、文字列のquote／補間文字のescape、dry-runの無変更、既存ID・ローカルFeature保持、marker異常時の全体無変更を確認した。実際のSwift／SwiftUIコンパイルはCIで検証する。

既存Zaiko Featureと専用テストはignoreしたローカルファイルのまま保持する。
