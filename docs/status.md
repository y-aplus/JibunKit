# 公開版・main・出荷候補の現在状態

更新日: 2026-09-15。公開安定版は[0.8.0/build10](https://github.com/y-aplus/JibunKit/releases/tag/0.8.0)（直前の正式版0.7.0）。P0/P1全12単位の合意範囲を実装・接続・検証・文書まで確認済み。mainへの統合と公開IPA/ZIPの無認証再取得・完全一致/CRC検査も完了。[出荷記録](verification/2026-09-15-0.8-release.md)を参照する。

## 0.8.0公開版

製品source `71ef1ffb4f84442bf8853c0c2e286c2bedd81d22`、[CI34967147135](https://github.com/y-aplus/JibunKit/actions/runs/34967147135)は5分16秒で成功。共通273件（skip2、失敗0）、Records11件、通常Release/metadata/署名/IPA検査が成功した。取得IPAの全entry CRC、本体・Widget・Shareの0.8.0/build10と既存ID、診断Widget kind/resource非混入も確認済み。

| 対象 | 現在の証拠 |
| --- | --- |
| P0の保存・寿命・管理・提示・追加更新 | 0.7.0のsource別CI/実機を維持。P1で変更した寿命・管理と通常UI/Filesは後続CIで回帰確認 |
| 共有/Files入力 | 初回保存先の誤拒否を修正。4e6a3f4のnative32件・完全host OS共有/再試行に加え、実機で文字列/URL/ファイル、直接開く、取消・再試行・再起動/B保持を確認 |
| Shortcuts | 6beb877でOS発見/正負加算/候補/保存済み操作/管理、4e6a3f4で取消・保存失敗・次回成功/B保持を実機確認。修正した診断制御はnative8件と管理UIでも検証 |
| 静的Widget | 独立/統合CI、通常版から診断版への更新galleryに加え、4e6a3f4実機で追加・描画・更新・A管理/B保持・上書き/Refresh保持を確認 |
| 通知・HTTP・Web | 対象別の通常host CIと6beb877実機で確認。通知添付/action/返信/前景方針、HTTP所有store/logout、Web保存/認証取消/片側削除、HTTP/Webの更新保持を含む |
| 通常IPAへの復帰 | 4e6a3f4でCounter/Reminder保持、通常Widgetの値/遷移、既存Counter Shortcutを実機確認 |

実機確認した4e6a3f4は0.7.1/build9で、正式0.7.1を公開したという意味ではない。そこから71ef1ffの製品差分は版番号のみ。旧sourceの証拠を残し、影響のない範囲を照合して再利用した。新0.8.0 IPAそのものの実機試験や、本runでSimulatorを再実行したとは記載しない。

実機の経緯は[操作別記録](verification/2026-09-14-0.8-device-check.md)、修正・失敗runは[追補](verification/2026-09-15-p1-device-followup.md)、合格条件との対応は[出荷evidence](verification/2026-09-15-0.8-evidence.json)へ保存している。通常IPAはCounter/Reminderと汎用Share Extensionを含む。受信先Featureにはoptional `incoming`登録が必要で、診断A/B・Records・ignored Zaikoは通常IPAに含めない。

## 残る範囲と観測限界

- P1の失敗再試行は最終の重複なし/B保持を実機確認したが、失敗直後の未取込み行は独立観測なし。保持の内部条件はCI証拠と分ける。
- Widgetは上書き/Refresh後の起動で保持を確認。再登録直後の単純な強制終了だけを独立して再試験してはいない。即時更新は保証しない。
- 通常版へ戻した後に診断Widgetの旧表示がホームへ残った。通常IPAに診断kind/resourceはなく、旧表示だけからコード継続・store再読込・データ削除を判定しない。
- SimulatorのSpotlight解除で過去に120秒超過、後続で約63秒の成功があった。実機は体感ほぼ即時で成功したが、遅延原因は未確定。集中モード下の通知配信も確認済み範囲へ含めない。
- P2/P3の音声・capture・位置・実OS background起動・Control/継続表示・外部identity・通常複数window等は未完。P0/P1完了を親D全体の完了と扱わない。

## 1.0の決定と文書

1.0は未達。受領済み[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)のP2-A全体/P2-B通常範囲/P2-Cの再利用可能な範囲という提案を踏まえ、0.8.0完了時にユーザーが正式境界を決める。

P単位の状態は[plan.json](delivery/plan.json)、D全体の残件は[台帳](coexistence-ledger.md)、責任は[共存原則](coexistence-boundaries.md)、版境界は[優先実装](implementation-priorities.md)が正本。過去のCI待ちや公開状態は、日付付き検証記録・履歴・過去release notesの当時の記録として読む。

0.7.0はP0全6単位を[CI/実機/公開取得で確認](verification/2026-09-13-0.7-release.md)した版。0.6.0の範囲と証拠は[当時の公開記録](verification/2026-09-12-0.6-release.md)へ保持し、新候補の結果へ読み替えない。
