# ミニアプリへのURL遷移

更新日: 2026-09-08

## 目的と実装

Widgetや外部リンクから対象のミニアプリを直接開ける共通経路を追加する。Featureの詳細画面や業務操作はこの段階では解釈しない。共通のMiniAppLinkがURL生成と登録済みIDへの解決を担い、ホストは既存AppNavigationへ接続する。Counter Widgetは同じAPIでURLを指定する。

不明IDや不正URLは現在の画面を維持する。URLを受けただけでデータを書き換えない。sheet中は下の遷移先のみ更新し、編集中のsheetを強制終了しない。

## 検証

- URL往復、未登録ID、無効ID、異なるscheme/host、余分なpath/query/fragment、認証情報・port・エンコードされた区切りをFoundationテストへ追加。
- 実際のURL受信による終了状態からの起動、起動中のCounter→Reminder→Counter切替、不明ID・未対応queryで画面維持をUIテストへ追加。
- CI結果待ち。Swiftを実行できないこのWindows環境では差分検査まで実施。
- Widgetの実際のタップは実機の確認範囲。URL受信テストとWidget本体のタップは区別する。
- バックアップFilesのSimulator障害は別件として継続記録する。今回のUIテストはFilesを経由しない。

## 共通ロジック・ビルドのCI結果

[run 34173854527](https://github.com/y-aplus/JibunKit/actions/runs/34173854527)、source `66807e402091fbfc19adefa01c22a6552d06e335`でURL生成・解析を含むFoundation全37件、Tuist雛形検証、通常アプリ・Widgetビルド、IPA検査・生成が成功。今回のrunはSimulator UIテストなし。URL受信・画面遷移のUI検証はrun 34173767891の結果で別に判断する。
