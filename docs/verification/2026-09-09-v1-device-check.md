# 1.0候補・Records接続の実機確認構成

基盤source: a27a91e。1.0.0 build 3。通常候補との差分はRecords Package/product、既存Integration 3ファイルの接続、Registry登録だけ。Feature本体と基盤処理は変更しない。通常配布にはRecordsを登録しない。

Counter/Reminderの識別子・App Group・保存値を維持する。検証用fixtureは組み込まない。Zaikoは含まない。

CI成功・IPA取得後にhashとrunを記録する。最終確認では既存データ維持、Widget/Shortcuts、Reminder通知、Records二件の日時指定・別々の配信と詳細遷移・片方の取消・Records復元後の通知取消と他Feature維持をまとめて確認する。現在は未確認で、ビルド成功を実機結果として扱わない。
