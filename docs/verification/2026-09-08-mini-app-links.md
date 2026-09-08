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

## 初回UI検証とテスト経路の修正

[run 34173767891](https://github.com/y-aplus/JibunKit/actions/runs/34173767891)、source `21c9179`。Counter・ReminderへURL起動する確認は成功したが、不明ID受信後にReminderを維持する確認で失敗した。テストログでは各`XCUIApplication.open`の後にLaunchとautomation session再設定があり、起動中の受信を確認するつもりで再起動経路を使っていた。

URL送信を`XCUIDevice.shared.system.open`に変更し、OSのscheme登録と起動中のURL受信を通して再検証する。ホストの実装と画面維持の合否条件は変更しない。[Appleのsystem API](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/system)を参照。

既存UI3件は成功。バックアップUIは既知のFiles障害で失敗し、回収したログにもFileProvider -1005 / resolver -1012と空URL配列を確認した。URLテストの失敗と区別する。後続の検索CI `34174278333`は修正前のテストを含むため、そのURL結果も同じ観点で扱う。

## 修正後のUI検証

[run 34174578083](https://github.com/y-aplus/JibunKit/actions/runs/34174578083)、source `2785761539c58e0c30a17656ef025ef7dd6e4a74`でURLテストが成功。OS経由のURL送信による終了状態からのCounter起動、起動中のReminder切替、不明ID・未対応queryで画面維持、Counterへの再遷移と一覧への復帰を確認した。

検索UIと既存UI3件も成功。共通テスト・雛形検証・通常アプリ／Widgetビルド・IPA検査は成功。全体のfailureはバックアップUIのFiles選択後の74行目のみ。URL遷移に関する今回のテスト修正は検証済みで、同条件の再実行は不要。Widget自体のタップ操作の実機確認は引き続き別の確認範囲。
