# 2026-09-07 レビュー修正の検証

対象ブランチ: `codex/simplify-mini-app-integration`

## 変更と責任の境界

- JibunKitCore: 同一プロセスの複数Storeによる読み取り・計算・保存の排他、IDにドットを含む場合の保存キー・通知prefixの分離。
- ZaikoFeature: バックアップの全件検証と旧形式の移行、配信済み・取消し済み通知の区別。
- 設計: 共通基盤の先行実装を許可し、個別アプリ・サンプルの先行完成を要求しない。Feature自身の不具合を基盤が吸収する契約にはしない。

## 検証経路

このPCにはSwiftとWSLディストリビューションがないため、ローカルでは差分・文書リンクを検査し、既存のGitHub Actionsを作業ブランチ上で手動実行する。`main`への統合やRelease公開は行わない。

- run [34086116427](https://github.com/y-aplus/JibunKit/actions/runs/34086116427): macOSの最低deployment target不足で`Date.now`のコンパイルに失敗。Package.swiftにmacOS 12をテスト実行条件として明記した。iOSアプリの最低OSは26.0のまま。
- run [34086196017](https://github.com/y-aplus/JibunKit/actions/runs/34086196017): 全39テスト成功。iOSビルドで既存の通知取消し処理がSetをArray引数へ渡す型エラーを検出し、修正した。
- run [34086375041](https://github.com/y-aplus/JibunKit/actions/runs/34086375041): 全41テスト成功。Swift 6.3.3が通知設定のBoolコールバックのIR生成中にクラッシュした。Bindingのsetterを明示的なclosureにして関数の直接変換を避けた。
- 最終run [34086629153](https://github.com/y-aplus/JibunKit/actions/runs/34086629153): source `075fbd6181aa12b3d905145b8e34c9e1643bd3dd`で全41テスト成功。Xcode 26.6のRelease／arm64 iOSビルド、App Intentsメタデータ、本体・Widget、識別子・署名・IPA整合性、artifact uploadが全step成功。コンパイル警告なし。署名検査コマンドに既存のパス指定の非推奨警告2件あり。
- artifact `JibunKit-ad-hoc`: 415,864 bytes（Actionsのartifact archive）。archive SHA-256: `7211ece4bee1ce32999eae16e535325d63bd9b2d9f3d99136a8209492110d160`。これはIPA単体のハッシュではない。
- ローカルでは`git diff --check`と、今回変更した文書のローカルリンク33件の検査が成功。最終run以降の変更はこの検証記録・変更履歴等の文書のみ。

## 回帰テストの範囲

- 同じsuite・キーを使う4つのCounterStoreから400回加算し、返り値が1〜400で保存値も400になること。
- overflowで保存値を変更せず、ロック解放後に別Storeから更新できること。
- `zaiko` + `backup.latest` と `zaiko.backup` + `latest`が別キーになること、通知prefixも分離され、既存3アプリの識別子を維持すること。
- 現行バックアップ・PWA v3・旧形式の正常読込み、空在庫のversion付き出力の再読込み、不正・部分不正・未知の版・重複・範囲外IDの拒否。
- 配信済み記録の維持、pending取消し後の再予約、停止期間の日時補正後も配信済みサイクルを維持すること。

## 未実施

SwiftのロジックテストとiOSビルドは、SideStore実機動作の代わりではない。実機での画面とShortcutsの併用、通知配信後の再入場、通知オフ→オン、停止→再開、バックアップ読込み、更新・再署名後の保存維持は未実施。

プロセス間の書込み排他は追加していない。Widgetは既存どおり読取り専用。ドット入りIDを旧方式で使った派生には、`docs/updating.md`に記載した所有キーを明示する移行が必要。
