# JibunKit 0.7.1 — 公開前の下書き

未公開。現在の安定版は0.7.0。2026-09-15のP1実機確認を区切りに、本体/Widget/Shareの0.7.1/build9候補を準備中。0.8の到達条件は未達のため、P1全体を完成と扱わない。

共有文字列の読込みを修正し、native29件と小hostのOS共有3件で文字列/URL/ファイルの取込み・内容一致を確認した。Shortcuts診断制御は永続化し、native実行・metadata比較と通常host管理を確認済み。完全P1 hostの共有・失敗再試行、修正後の通常/診断IPAは現在検証中。

前候補ではHTTP/Web/通常状態の通知、通常版への復帰と既存Counter/Reminder・Widget/Shortcutの実機確認が成功。共有入力の再確認、OS Shortcutsでの取消/失敗診断、実機Widget A/Bの表示・管理・更新保持が残る。SimulatorでのWidget gallery成功を実機成功へ拡張しない。

[実機結果](docs/verification/2026-09-14-0.8-device-check.md)と[検証結果・再利用範囲](docs/verification/2026-09-15-p1-device-followup.md)を参照。必要実機、配布整合性、文書と出荷範囲を確認して公開内容を確定する。未取得の配布URL・digestや成功結果は記載しない。
