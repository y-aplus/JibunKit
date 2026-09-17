# 公開版・main・出荷候補の現在状態

更新日: 2026-09-17。公開安定版は[0.8.3/build13](https://github.com/y-aplus/JibunKit/releases/tag/0.8.3)（前版0.8.2/build12）。音声・撮影/scanの対象別実機、CI35169921272、main統合、公開IPA/ZIP無認証取得と整合性確認まで完了。[出荷照合](verification/2026-09-17-0.8.3-release.md)。

P2-1/P2-2の採用通常範囲はcomplete。306874fで再生/録音・写真/音声動画、a142108で文書保存/取消・QR・イヤホン抜去停止・通常版復帰後の既存データ保持を確認。native28件と通常通知UIはCI35102558612のsource付き証拠を、版変更だけの出荷へ再利用した。写真初回の不明エラー、以前のLive B単発値差分は原因未確定として保持。1.0全体は未完、次の境界は背景実行と位置（P2-B）。以下の旧版節はsourceを明示した履歴。

## 開発中の背景処理・位置情報

**実機でda62672診断版の起動直後終了を確認し、修正中。** SIGTRAPの起動処理を特定。再署名後の背景ID対応とFeature別の起動失敗処理を0672c74へ追加し、再CI待ち。旧診断版の再試行は不要。以下のCI成功は実機起動成功を意味しない。

現在の開発branch `codex/p2-background-location`では、source `da62672`の[CI35176070341](https://github.com/y-aplus/JibunKit/actions/runs/35176070341)が成功した。共有389件（既存Keychain2skip）、背景10件・位置7件のnative試験、通常検索UI、通常/診断IPAを検証。P2-3/P2-4は、実OS背景起動・位置/Region/iBeaconの実測を残すためpartial。mainの公開runtimeは0.8.3のままである。[今回の確認範囲](verification/2026-09-17-p2-background-location-device.md)。

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
- P2/P3の位置・実OS background起動・継続表示の未解決観測・外部identity・通常複数window等は未完。音声・captureは0.8.3の採用通常範囲を完了し、特殊構成や初回写真エラーの未解明観測と区別する。P単位の完了を親D全体の完了と扱わない。

## 1.0の決定と文書

1.0は未達。2026-09-15にユーザーが[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)の推奨境界を採用した。P2-A全体とP2-B通常範囲、採用したP2-Cを実装/接続/検証/説明まで閉じる。操作Widget/Controlは0.8.1で完了。P2-Lは対象別実機と通常版復帰を確認し、0.8.2で公開済み。Live Bの単発の値差分は原因未特定で、P2-5はpartialを維持する。

P単位の状態は[plan.json](delivery/plan.json)、D全体の残件は[台帳](coexistence-ledger.md)、責任は[共存原則](coexistence-boundaries.md)、版境界は[優先実装](implementation-priorities.md)が正本。過去のCI待ちや公開状態は、日付付き検証記録・履歴・過去release notesの当時の記録として読む。

0.7.0はP0全6単位を[CI/実機/公開取得で確認](verification/2026-09-13-0.7-release.md)した版。0.6.0の範囲と証拠は[当時の公開記録](verification/2026-09-12-0.6-release.md)へ保持し、新候補の結果へ読み替えない。

## 0.8.0後の開発

1.0範囲の採用に伴い、plan.json/schema2へP2の13追跡単位と7つのCI境界を追加した。P2のうち10単位は必須機能、3単位は低負荷候補/P2-Cの採否と採用範囲を扱う。単なる台帳件数を完成機能数とはしない。ローカルdelivery検査19件が成功し、通常機能の省略・条件付き未検証・長すぎるrun見積りを拒否する。

P2-WはCI35027469173（e984d44）で独立A/B/統合build、metadata10定義比較、native4件、通常管理UI1件、診断IPAが成功。通常job34979381516の共有290件（skip2）、Records11件、別process probe、通常IPA/UI13件/Files往復1件は差分を確認して再利用した。初回無効化はSimulatorで約88秒、通知終了後のSpotlight接続中断も記録されており、遅延の解消とは扱わない。

e984d44の診断IPAで一括実機確認が完了。Widget/Control各二候補・選択変更・背景からの加算、アプリ/端末再起動、同IPA上書き/SideStore Refresh、片側項目削除/無効化/全削除/再登録/選択JSON復元と古い設定拒否・B保持、通常IPA復帰が成功した。Control設定は編集状態で開く。実機の無効化はほぼ即時。本体表示も手動再読込みなしで更新されたが、一般的な即時更新保証とはしない。[操作記録](verification/2026-09-15-p2-widget-control-device.md)。

0.8.1/build11のsource88ab7cbはCI35038442208で成功。実行コードは実機確認版と同じで、製品差分は3bundle版のみ。main統合・0.8.1正式公開・IPA/ZIP無認証再取得/一致/CRCまで完了した。P2-7はcomplete。1.0全体は未完で、次はP2-LのLive Activities/AlarmKit。旧sourceのCI/実機を今回sourceへ無条件に読み替えない。[出荷照合](verification/2026-09-16-0.8.1-release.md)・[接続ガイド](guides/interactive-widgets.md)。

## 0.8.2のP2-L

Live Activities/AlarmKitの共通所有・寿命・照合、通常管理/復元接続を実装。共通326件（skip2）、Records11件、独立A/B/Combinedのapp/Widget/metadata、Live native4/Alarm native2、通常診断host管理UI1、通常/診断IPAが成功。OS開始/更新/停止・Alarm標準stop callback・片側管理/復元・通常版復帰の一括実機を確認。Live Bが上書き前に期待230ではなく200と表示された観測は原因未特定で、210からの限定再確認では再現しなかった。P2-5はpartialを維持。0.8.2/build12はCI35075825942と取得IPA検査が成功し、公開IPA/ZIPの再取得まで完了。実4Featureの非初期値/世代について片側管理・JSON復元後の他方保持を自動試験で確認した。[一括実機手順](verification/2026-09-16-p2-continuing-surfaces-device.md)・[source別証拠](verification/2026-09-16-p2-continuing-surfaces.md)。
