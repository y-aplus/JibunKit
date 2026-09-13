# P1-A 共有入力・Shortcuts・静的Widgetの契約

2026-09-13着手。機能baselineはmain13fa2fe（P0完了/0.7.0公開済み、製品baa041f）。この契約commitを全レーンの共通baselineにする。Issue #6は需要推定案として受領し、ユーザー回答により1.0正式境界は0.8.0完了時に確定する。P1の範囲はIssue #5のまま。

## 対象と分担

P1-3（親D12/D26）の外部ファイル/Share入力、P1-1（D27）のOS Shortcuts実利用、P1-2（D26）の二静的Widget通常接続を一括して閉じる。Core/Definition/Registry/Project/rootPackage/workflow/台帳と通常hostは親が所有する。

- 親: 共有入力の所有先選択、security-scoped URL/NSItemProviderのアクセス寿命、extensionからの持続する受信、hostの正常/取消/失敗/再試行。共通APIと最終統合/CI。
- Shortcuts別スレッド: Tests/PackageAppIntentsと必要な専用fixture/UI tests、docs/guides/package-app-intents.md/feature-app-shortcuts.mdの通常接続・実機手順。既存native identity検査と直接perform証拠を保持し、通常Definition/永続storeへの接続、引数/戻り値/entity候補/取消とA無効化/削除時のB保持をまとめる。
- Widget別スレッド: Tests/PackageWidgetsと必要な専用fixture/UI tests、docs/guidesの静的Widget接続手順。通常管理/共有storeからの二Widget描画、A更新/無効化/削除/再登録とB保持、kind/翻訳/出荷時登録条件をまとめる。

別スレッドはSol low。共有ファイルの必要変更は提出文書に正確な差分案を記載し、直接編集しない。兄弟の未検証変更に依存しない。既存public APIを使い、Core変更が必要な場合のみ親へ一括して要件を伝える。新しいAPI/fixtureの設計ではmainのMiniAppManagement/FeatureLifetime/RestoreCoordinator/Counter実装を参照する。

## 共通契約

- Feature ID、永続Intent/entity/query識別子、Widget kindと保存namespaceは独立appと統合hostで安定。既存Counterの識別子/保存値は変えない。
- 全入口でP0のowner availabilityと通常保存/復元の調停を維持。無効化/削除済みownerの書込を拒否し、別ownerを巻き込まない。UIが見えていないことだけで終了/無効化としない。
- 通常FeatureはCore非依存でもよく、Integration/extension側からサービスを接続する。Core wrapperやソース生成を追加すること自体は目的にしない。二つの検証Featureは実際の永続storeと通常Definitionを使う。
- cancellation/failureを成功扱いせず、部分処理を区別。保存失敗で以前の値や他Featureを壊さない。操作の再試行とアプリ再起動保持を確認する。
- Widgetのreload呼出成功は実OS描画成功ではない。OS Shortcutsの発見/候補/保存/引数/戻り値/取消は直接performでは代替できない。端末での未確認は明記して0.8候補の一括確認へ予約する。
- Widgetの静的二owner表示はP1。設定可能/操作可能WidgetとControlのP2をこの境界へ追加しない。
- Shareは汎用入力を指定Featureへ引き渡す。OCR等の業務処理は提供しない。URL/文字列/ファイルの所有と一時ファイル解放を扱い、任意extension自動統合や実Universal Link一般化へ広げない。

## 提出と検証

各レーンは実装・通常接続fixture・期待する操作列/失敗試験・docsを一括commit/pushして提出する。報告はcommit、変更契約、test対応、ローカル結果、未検証、親が行う共有編集とCI入力案。ローカルWindowsではSwift/Xcodeを検証済みとしない。子CIは禁止。親の一括レビューは初回提出＋必要なまとめ修正を基本にする。

親が全レーンを統合し、正確なselectors/入力と元証拠の再利用条件を固定してpreflightを通す。初回3run、各job見込み30分以下/timeout45分以下。共通buildを使える同構成の試験をまとめ、失敗例ごとのrunを作らない。通常IPA/主要回帰、生成二ownerのOS入口/metadata、共有extension/native入力を必要構成に分ける。具体selectorsと実行時間見積りは実装提出後に確定し、未確定でdispatchしない。

CI完了は既存OS監視→codex queueの一回通知。gh run watch --interval、モデル定期poll、子提出ごとのCIは禁止。実機は原則0.8.0候補で一括し、P1-A段階でdevice条件を勝手に合格にしない。

## 受入対応

- P1-1.metadata: 単独A/B→統合→A寄与削除でnative Intent/entity/query/引数/戻り値の識別子を照合。通常接続のstore更新/取消/無効化拒否/B保持を追加。
- P1-1.os: OS Shortcutsから発見・候補選択・保存したworkflow実行・引数/戻り値/取消と他owner保持。0.8候補へ予約。
- P1-2.widget: 二静的Widgetのgallery追加・実描画、A更新/管理削除後のB保持、通常出荷の接続。単独timelineだけで閉じない。
- P1-2.device: 上記の通常OS操作を候補IPAで一括。0.8へ予約。
- P1-3.routing: 未知/曖昧/対象無効/取消/失敗、scope解放、持続した受信と一時ファイルの寿命、B保持。
- P1-3.os: OS共有シート/外部ファイルからの対象選択・成功/取消/失敗/再起動保持。0.8へ予約。

P0のCIと実機証拠は変更差分をレビューして再利用し、所有/保存/提示/管理に影響する箇所だけ再検証する。公開0.7.0のtag/IPAを変更しない。
