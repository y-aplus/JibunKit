# 公開版・main・開発branchの現在状態

2026-09-15現在、開発branch `codex/p1-device-gallery-followup` で0.7.1/build9候補を準備中（正式版は未公開）。前候補の実機ではHTTP/Web/通常状態の通知と通常IPA復帰が成功。09927a6の再確認では文字列/URL/ファイルの共有保存と本体内部投入がinvalidInputで失敗し、今回の実機OSは27.0と判明した。追加件数/B状態は未確認。

保存先判定を修正した`4e6a3f4`は通常34958710691・診断/native34958712557が成功。共通273件(skip2)、native32件、完全hostのOS共有/再試行/再起動保持/B保持を確認。旧パス判定の誤拒否をmacOSで再現したが、iOS26 Simulatorでは再現しておらず、iOS27.0実機でも修正後の文字列共有保存・本体取込みが成功し、A件数1を確認。URL/ファイルも取込み成功し、A件数3・内容3行を確認。B取込みと共有取消後のA/B件数保持も実機成功。保存後失敗/再試行の手順後も未取込みなし・A4件/B不変を実機確認。再起動後も受信A4件/B件数・内容を保持し、Widget一覧の機能A/B表示も実機成功。ホームのWidget A/B描画・本体値一致・各値更新も実機成功（指定加算回数は逆、体感では即時）。片側管理、上書き/Refresh保持は未確認。[保存先修正版prerelease r2](https://github.com/y-aplus/JibunKit/releases/tag/p1-device-check-20260915-r2)の通常/診断IPAは0.7.1/build9。iOS27固有差分はchat調査へ委ね、追加preview CIは準備のみで未投入。

[検証結果と再利用範囲](verification/2026-09-15-p1-device-followup.md)、[実機結果と残件](verification/2026-09-14-0.8-device-check.md)を参照。共有、Shortcut取消/失敗、Widget表示/管理/更新保持と出荷確認が残り、0.8.0未達。

更新日: 2026-09-15。[0.7.0](https://github.com/y-aplus/JibunKit/releases/tag/0.7.0)を公開済み。P0全6単位をCIと2026-09-13の一括実機確認で検証済み。P1/0.8.0は未完了。需要調査Issue #6は受領済みで、1.0の正式範囲は0.8.0完了時に確定する。

## 公開版0.7.0

- [Release](https://github.com/y-aplus/JibunKit/releases/tag/0.7.0) / [IPA](https://github.com/y-aplus/JibunKit/releases/download/0.7.0/JibunKit.ipa)。通常Counter/Reminder、app/Widget0.7.0 build8。
- tag commit `857c2358e6d18b883abbcd42fb9a92ed104d5074`。製品/IPAはCI34705653297の`baa041f`と同一で、差分は文書/証拠のみ。
- P0全6単位をCIと一括実機で確認。通常IPA上書き後も変更したCounter/Reminderを保持し、軽い回帰もユーザー確認済み。
- 公開IPAを認証なしで再取得し、実機確認済みIPAとの全byte一致・CRC・GitHub asset digestを確認。[公開記録](verification/2026-09-13-0.7-release.md)。
- P1は未完了。需要調査Issue #6は受領し、1.0の正式境界はユーザー判断により0.8.0完了時に確定する。

## 前版0.6.0の記録

- [Release](https://github.com/y-aplus/JibunKit/releases/tag/0.6.0) / [IPA](https://github.com/y-aplus/JibunKit/releases/download/0.6.0/JibunKit.ipa)。本体・Widgetは0.6.0 build 7。
- sourceは`5e8683f76edbbaeb17a29ed02c1ae6068bc8f759`。通常IPAはCounter/Reminder。
  Recordsは参照Package、Zaikoと診断fixtureは通常IPAに含めない。
- 独立Featureの雛形・単独実行・組込み、保存/通知/URL、選択JSON・添付ZIPバックアップと復元を提供。
- 0.6.0では共有background refreshの永続要求・調停・復旧API、Package翻訳のmixed localization、
  Package Widgetの接続/描画/片側更新後の他方保持の検証を追加。
- 出荷CI34684114252で共有203試験（既存skip 2件）、通常UI11件、Files経由JSON選択復元が成功。
  通常UIに添付ZIP往復を含む。公開IPAの再取得・全byte一致・CRCも確認済み。
- 0.6.0そのものの新しい実機試験は行っていない。以前のユーザー実機結果は各sourceの証拠として保持。
  詳細は[release notes](../release-notes-0.6.0.md)と[公開検証記録](verification/2026-09-12-0.6-release.md)。

## 公開版0.7.0の追加（0.6.0比）

| 変更 | 確認できたこと | 残る条件 |
| --- | --- | --- |
| 純Swift SDKのmodule alias比較 | macOSの単独A/B・統合、iOS Tuist hostで両版/設定の表示とB書込後のA更新・B保持。iOS試験34686272759成功 | iOSは公開product名を分ける依存manifest編集が必要。同名product構成は失敗。同一identityの複数version、binary/C/ObjC、OS globalsは未解決 |
| P0-Aの寿命・保存・終了診断 | 通常34691452980、生成34694032847成功。Feature開始/終了/再試行、JSON/添付とSQLiteの保守、他owner保持、終了進捗。共通216試験（skip2）、Records11、生成host比較5件 | 2026-09-13の実機で選択復元と診断表示を確認。高度なinstance/別process writerは残る。詳細は[P0-A記録](verification/2026-09-12-p0-a.md) |
| P0-Bの提示・同意・アプリ内管理 | 同sourceの生成34700435807（8件）と通常34702137986（共通241/skip2、Records11、通常UI13、Files選択JSON復元）成功。提示中URL遷移、UIKit終了、無効化/再登録/削除/失敗再試行/B保持 | 2026-09-13の実機で同意/管理/提示、外部URL切替、Widget/Shortcut反映を確認。[P0-B記録](verification/2026-09-12-p0-b.md) |
| shared refresh実機用診断fixture | 34684495878でiOS注入試験16件と診断app/UI targetのコンパイルが成功 | 実OSのpending受付・launch・期限は未検証。実機用IPAの公開や操作依頼は未実施 |

上記は0.7.0に含む追加であり、0.6.0配布物の機能・検証に含めない。
[SDK記録](verification/2026-09-12-package-sdk-aliases.md) / [refresh診断記録](verification/2026-09-12-shared-refresh-native.md)。

P0-Cの接続診断、Registry漏れ/修正、同じiOS hostへのAだけのPackage更新とB/resource保持もCI34705653297で確認済み。[P0-C記録](verification/2026-09-12-p0-c.md)。通常IPA更新後のCounter/Reminder保持と軽い回帰もユーザー確認済み。

## 次の版の境界と未達

[Issue #5の優先順位](implementation-priorities.md)を導入した。P0の6単位完了を0.7.0、P0を維持したP1の6単位完了を0.8.0とする。
途中の公開は0.6.x/0.7.xで行う。P0-5はアプリ内でのFeature無効化・削除を必須とする。
P0は全6単位の出荷条件を確認済み。P1は部分成果があり未完了。5つの[CI境界](ci-boundaries.md)を設定し、minorごとの文書確認を必須にした。
CI34705653297（source baa041f、22分）で共通244試験（skip2）、Records11、native接続診断6ケース、macOS互換更新、生成hostの登録漏れ/修正とiOSのAだけの互換更新、通常URL回帰、通常/診断IPAの検査が成功。P0のCIと実機一括確認は完了。0.7.0公開済み。 詳細は[P0-C記録](verification/2026-09-12-p0-c.md)と[実機手順](verification/2026-09-13-0.7-device-check.md)。
1.0の最終対応範囲は受領済みのP2/P3需要調査を踏まえ、0.8.0完了時にユーザーが決定する。

## 残っている統合差分

補完責任は[共存原則](coexistence-boundaries.md)、版の対象範囲は上記の優先実装計画に従う。現在の判定と残作業は
[統合差分台帳](coexistence-ledger.md)で管理する。SDKの部分成功や0.6.0公開で1.0達成とはしない。
複数OS window、高度な提示・同意、音声/capture資源調停、OS起動を伴うbackground、
Control/継続表示、任意SDKや外部identity等に未実装・未検証が残る。

[1.0完成計画](superpowers/plans/2026-09-08-jibunkit-1.0.md)は再開時に扱う作業の枠組み。
[停止時引継ぎ](verification/2026-09-12-development-checkpoint.md)にbranch・証拠・保持ファイルを記録した。
今回の再開は2026-09-12のユーザー指示による。需要調査[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)を2026-09-13に受領。P2-A全体とP2-B通常範囲を原則1.0へ含め、P2-Cを再利用可能な範囲で追加し、P3一般化は後段とする推奨境界は提案として保持し、ユーザー判断により0.8.0完了時に正式境界を確定する。

## 文書の読み分け

現在の手順は`docs`直下と`docs/guides`、現在状態はこの文書と台帳を参照する。
`docs/history`、日付付き検証記録、調査スナップショット、過去のrelease notesは履歴であり、
古いsourceの結果を新しいsourceへ自動的に引き継がない。
各公開tag内の文書は出荷時点で固定されているため、公開後の状態説明はmainの文書を参照する。開発branchの成果はその旨を明記する。


## mainのP1-A追加（公開0.7.0には含まれない）

共有入力の持続する受信・取消・冪等再試行、通常保存/管理へ接続した二Package Intents、二静的Widgetの通常接続を追加した。P1-Aの実機以外の受入条件は確認済み。P1-1/2/3全体は実機条件が残るためpartialを維持し、P1-Bの通知/HTTP/Webと合わせて0.8.0候補で確認する。1.0の正式境界はユーザー判断により0.8.0完了時に確定する。

source `77b5f5d` のrun34794545131で共有262件（skip2）、P1通常host UI3件、通常UI13件、Files復元1件、Records UI2件が成功した。run全体は45分上限によるcancelledで、成功と書き換えない。テストとartifact公開は終了しており、チェックrunの時間超過annotationと個別結果を照合して採用した。native Intents8件・Widget7件と元のP0/接続証拠はsource差分を確認して再利用する。[P1-A記録](verification/2026-09-13-p1-a.md)。

通常IPAはCounter/Reminderに加えて汎用Share Extensionを埋め込む。P1の検証用A/B Feature、Records、ローカルZaikoを出荷Featureとして自動追加しない。共有を受け取る独自Featureにはincomingの登録が必要。現在の公開IPAは0.7.0のままで、ここに記載したmainの追加を公開版の保証と混同しない。

## P1-B開発branch（main未統合、0.8未完成）

`codex/p1-b-notifications`で通知添付の寿命管理、停止後logout、通常HTTP/Webの二Feature接続を実装・検証した。端末内HTTP/認証fixtureは実装済みで、PCサーバー不要の診断IPAを生成済み。HTTP/通知・通信fixtureはrun34816553410、Web保存/取消/drainは34819734774、無効化/認証と直接Spotlight比較は34823801940で成功。通常回帰は34802338245から影響差分を照合して再利用する。各run全体の失敗/取消と成功したmethodを分けて[P1-B記録](verification/2026-09-14-p1-b.md)へ残す。

Simulatorの初回Spotlight解除は完了表示まで約63秒かかり、以前の120秒超過の原因は未確定。2026-09-15の実機結果は受領済みで、現在の残件は先頭と実機記録に集約する。0.8文書/出荷gateと1.0境界判断は未完了。前候補の表示0.7.0/build8と、準備中の0.7.1/build9を区別する。

P1の[診断prerelease](https://github.com/y-aplus/JibunKit/releases/tag/p1-device-check-20260914)を配布済み。診断6beb877/通常8b5b8b8のIPAとZIPを公開再取得で照合し、2026-09-15に一括実機結果を受領済み。これらは前候補であり、共有入力修正後の再確認用IPAではない。正式0.8公開でもない。

旧修正候補09927a6の[CI・配布証拠](verification/2026-09-15-p1-refreshed-candidate-evidence.json)は履歴として保持する。実機で保存失敗を確認したため、新しい確認には先頭の4e6a3f4候補を使う。
