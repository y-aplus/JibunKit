# JibunKit 0.7.1 — 公開前の下書き

未公開。現在の安定版は0.7.0。2026-09-15のP1実機確認を区切りに、次の候補は本体/Widget/Shareの0.7.1/build9を準備する。0.8の到達条件は未達のため、P1全体を完成と扱わない。

HTTP/Web/通常状態の通知、通常版への復帰と既存Counter/Reminder・Widget/Shortcutは[前候補の実機結果](docs/verification/2026-09-14-0.8-device-check.md)を得た。これを新sourceの未確認部分へ自動的に引き継がない。

共有入力の文字列変換とShortcuts診断制御の永続化を修正し、native共有25件、Intent実行8件とUI1件、単独/統合metadata比較をCI34881183837で確認済み。別OS文脈でのShortcuts実行やShare Extensionの実動作を、この成功だけで検証済みとはしない。共有URL保存とWidget galleryでのA/B非表示は切り分け中。通常IPA/主要回帰、候補inventory、必要な再実機、互換性・出荷範囲を確認してから公開内容を確定する。配布URL・digest・成功結果はまだ記載しない。
