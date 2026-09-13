# 公開版とmainの現在状態

更新日: 2026-09-13。0.7.0 build8出荷候補のP0全6単位をCIと2026-09-13の一括実機確認で検証済み。正式公開前の安定版は0.6.0。P1/0.8.0は未完了、1.0の範囲は需要調査後に決定する。

## 公開版0.6.0

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

## 0.7.0出荷候補の追加（0.6.0比）

| 変更 | 確認できたこと | 残る条件 |
| --- | --- | --- |
| 純Swift SDKのmodule alias比較 | macOSの単独A/B・統合、iOS Tuist hostで両版/設定の表示とB書込後のA更新・B保持。iOS試験34686272759成功 | iOSは公開product名を分ける依存manifest編集が必要。同名product構成は失敗。同一identityの複数version、binary/C/ObjC、OS globalsは未解決 |
| P0-Aの寿命・保存・終了診断 | 通常34691452980、生成34694032847成功。Feature開始/終了/再試行、JSON/添付とSQLiteの保守、他owner保持、終了進捗。共通216試験（skip2）、Records11、生成host比較5件 | 2026-09-13の実機で選択復元と診断表示を確認。高度なinstance/別process writerは残る。詳細は[P0-A記録](verification/2026-09-12-p0-a.md) |
| P0-Bの提示・同意・アプリ内管理 | 同sourceの生成34700435807（8件）と通常34702137986（共通241/skip2、Records11、通常UI13、Files選択JSON復元）成功。提示中URL遷移、UIKit終了、無効化/再登録/削除/失敗再試行/B保持 | 2026-09-13の実機で同意/管理/提示、外部URL切替、Widget/Shortcut反映を確認。[P0-B記録](verification/2026-09-12-p0-b.md) |
| shared refresh実機用診断fixture | 34684495878でiOS注入試験16件と診断app/UI targetのコンパイルが成功 | 実OSのpending受付・launch・期限は未検証。実機用IPAの公開や操作依頼は未実施 |

このmainの追加を0.6.0配布物の機能・検証に含めない。
[SDK記録](verification/2026-09-12-package-sdk-aliases.md) / [refresh診断記録](verification/2026-09-12-shared-refresh-native.md)。

P0-Cの接続診断、Registry漏れ/修正、同じiOS hostへのAだけのPackage更新とB/resource保持もCI34705653297で確認済み。[P0-C記録](verification/2026-09-12-p0-c.md)。通常IPA更新後のCounter/Reminder保持と軽い回帰もユーザー確認済み。

## 次の版の境界と未達

[Issue #5の優先順位](implementation-priorities.md)を導入した。P0の6単位完了を0.7.0、P0を維持したP1の6単位完了を0.8.0とする。
途中の公開は0.6.x/0.7.xで行う。P0-5はアプリ内でのFeature無効化・削除を必須とする。
P0は全6単位の出荷条件を確認済み。P1は部分成果があり未完了。5つの[CI境界](ci-boundaries.md)を設定し、minorごとの文書確認を必須にした。
CI34705653297（source baa041f、22分）で共通244試験（skip2）、Records11、native接続診断6ケース、macOS互換更新、生成hostの登録漏れ/修正とiOSのAだけの互換更新、通常URL回帰、通常/診断IPAの検査が成功。P0のCIと実機一括確認は完了。正式公開前。 詳細は[P0-C記録](verification/2026-09-12-p0-c.md)と[実機手順](verification/2026-09-13-0.7-device-check.md)。
1.0の最終対応範囲はP2/P3需要調査後にユーザーが決定する。

## 残っている統合差分

補完責任は[共存原則](coexistence-boundaries.md)、版の対象範囲は上記の優先実装計画に従う。現在の判定と残作業は
[統合差分台帳](coexistence-ledger.md)で管理する。SDKの部分成功や0.6.0公開で1.0達成とはしない。
複数OS window、高度な提示・同意、音声/capture資源調停、OS起動を伴うbackground、
Control/継続表示、任意SDKや外部identity等に未実装・未検証が残る。

[1.0完成計画](superpowers/plans/2026-09-08-jibunkit-1.0.md)は再開時に扱う作業の枠組み。
[停止時引継ぎ](verification/2026-09-12-development-checkpoint.md)にbranch・証拠・保持ファイルを記録した。
今回の再開は2026-09-12のユーザー指示による。需要調査[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)を2026-09-13に受領。P2-A全体とP2-B通常範囲を原則1.0へ含め、P2-Cを再利用可能な範囲で追加し、P3一般化は後段とする推奨境界の正式採用を確認中。

## 文書の読み分け

現在の手順は`docs`直下と`docs/guides`、現在状態はこの文書と台帳を参照する。
`docs/history`、日付付き検証記録、調査スナップショット、過去のrelease notesは履歴であり、
古いsourceの結果を新しいsourceへ自動的に引き継がない。
0.6.0タグ内の文書は出荷時点で固定されているため、公開後の状態説明はmainの文書を参照する。
