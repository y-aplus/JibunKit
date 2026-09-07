# 2026-09-07 共通基盤の統合検証

## 対象

Zaikoの試験移植を除き、Feature所有の定義・Root View・保存と通知のContext、共通保存排他、ホストのNavigationStackと通知delegateを統合する。共通基盤の先行実装は許容し、個別アプリの完成を前提にしない。Feature固有の入力検証や通知条件はFeature側が担当する。

Zaikoのソースと専用テストはローカルのignore対象として保持し、PackageとRegistryには登録しない。移植の履歴と実機確認記録は`codex/simplify-mini-app-integration`に保存する。

## 検証

- Foundationテスト: ID・保存namespace・通知prefixの分離、Contextと既存保存キーの互換性、CounterとReminderの独立保存。
- Counterの並行更新: 同一suite・キーの4つのStoreから400回加算。overflow時も保存値を維持し、ロックを解放する。
- iOSビルド: 本体・Widget・App Intents metadata、署名とIPA整合性。
- Simulator: CounterとReminder間の移動、保存、プロセス再起動、通知配信とタップ後の遷移。

Zaiko除外後のCIは[run 34105471139](https://github.com/y-aplus/JibunKit/actions/runs/34105471139)、source `570735369d299c2dec8087122820f06872ba3fa4`で全step成功。Foundation 21テストとSimulator UI 2テスト（保存・再起動・通知遷移）が全件合格した。Release iOSビルド、本体・Widget・App Intents metadata、署名・IPA整合性と成果物の保存も成功。検証後の変更はこの記録のみ。以前の移植用IPAでは、利用者が実機でCounter Widgetとショートカットの動作を確認した。この結果を除外後のIPAの実機検証と混同しない。今回のmain統合はリリース公開を含まない。

## 保存の境界

排他は同一プロセス内で、全writerが共通APIを使う場合に限る。Widgetは読取り専用。プロセス間の書込み排他は提供しない。ドット入りIDの旧namespaceを使う派生の移行は[更新手順](../updating.md)を参照する。

## 移植元への報告

Zaiko固有の問題は現行main `f8d47a4`のコードでも確認し、単独版への適用・検証が必要なためIssueとして報告した。

- [バックアップ読込みの検証と状態維持 #1](https://github.com/y-aplus/zaikoIOSapp/issues/1)
- [取消した未配信通知の再予約 #2](https://github.com/y-aplus/zaikoIOSapp/issues/2)
- [非有限数と残日数の整数変換 #3](https://github.com/y-aplus/zaikoIOSapp/issues/3)
