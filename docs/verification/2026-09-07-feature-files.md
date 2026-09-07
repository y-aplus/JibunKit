# Featureのファイル保存基盤

UserDefaultsを唯一の保存方式にせず、Featureがファイル形式・DBを選べるようにする。コンテナ解決と保存先の分離を基盤が担当し、データ形式・移行・バックアップはFeatureが所有する。

- [x] MiniAppFilesの保存先URL・Data読書きAPIを実装。
- [x] 明示コンテナとSideStore App Group解決の両経路を用意。
- [x] 保存方式と排他・移行の責任境界を文書化。
- [x] CIで独立保存・再生成後の読込み・不正名の無変更・空と未作成の区別・署名済みgroup解決を検証。
- [x] iOSビルドと既存UIの回帰を確認。

既存Featureの保存方式やデータは変更していない。テストのコンテナは一時ディレクトリであり、実機App Group内のファイル書込み成功を示すものではない。Zaikoはローカルignore状態を維持する。

## CI結果

[run 34109047738](https://github.com/y-aplus/JibunKit/actions/runs/34109047738)、source `f8645a401cdb02d95927ad2a2dcb74f1ea5ca77d`で全step成功。

- 新規MiniAppFilesテスト4件を含むFoundation 25テスト成功。隔離した生成Feature構成でも25件成功。
- Python雛形生成テスト4件成功。
- 生成Featureを含むiOS Releaseビルドと通常構成のiOS Releaseビルド成功。
- 本体・Widget・App Intents metadata、署名・IPA整合性の検査とartifact保存成功。
- Simulator UIテスト2件（保存・再起動、通知配信・遷移）が成功。

検証後はこの記録だけを更新した。端末固有のApp Groupアクセスは上記の検証範囲と区別する。
