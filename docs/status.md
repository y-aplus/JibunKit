# 公開版とmainの現在状態

更新日: 2026-09-12。実装基準点はmain `efa47e6`（SDK iOS比較の統合・検証記録まで）。
その後の文書整理は製品コードを変更しない。ユーザー指示で開発スレッドは停止中。
この文書更新は開発の自動再開を意味しない。

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

## 0.6.0後にmainへ入った変更（未リリース）

| 変更 | 確認できたこと | 残る条件 |
| --- | --- | --- |
| 純Swift SDKのmodule alias比較 | macOSの単独A/B・統合、iOS Tuist hostで両版/設定の表示とB書込後のA更新・B保持。iOS試験34686272759成功 | iOSは公開product名を分ける依存manifest編集が必要。同名product構成は失敗。同一identityの複数version、binary/C/ObjC、OS globalsは未解決 |
| shared refresh実機用診断fixture | 34684495878でiOS注入試験16件と診断app/UI targetのコンパイルが成功 | 実OSのpending受付・launch・期限は未検証。実機用IPAの公開や操作依頼は未実施 |

このmainの追加を0.6.0配布物の機能・検証に含めない。
[SDK記録](verification/2026-09-12-package-sdk-aliases.md) / [refresh診断記録](verification/2026-09-12-shared-refresh-native.md)。

## 次の版の境界と未達

[Issue #5の優先順位](implementation-priorities.md)を導入した。P0の6単位完了を0.7.0、P0を維持したP1の6単位完了を0.8.0とする。
途中の公開は0.6.x/0.7.xで行う。P0-5はアプリ内でのFeature無効化・削除を必須とする。
P0/P1はいずれも部分成果があるが未完了。5つの[CI境界](ci-boundaries.md)を設定し、minorごとの文書確認を必須にした。
現在進めたのは計画・運用toolの整備であり、製品開発の停止は解除していない。
1.0の最終対応範囲はP2/P3需要調査後にユーザーが決定する。

## 残っている統合差分

補完責任は[共存原則](coexistence-boundaries.md)、版の対象範囲は上記の優先実装計画に従う。現在の判定と残作業は
[統合差分台帳](coexistence-ledger.md)で管理する。SDKの部分成功や0.6.0公開で1.0達成とはしない。
複数OS window、一般の提示・同意・音声/capture資源調停、OS起動を伴うbackground、
Control/継続表示、任意SDKや外部identity等に未実装・未検証が残る。

[1.0完成計画](superpowers/plans/2026-09-08-jibunkit-1.0.md)は再開時に扱う作業の枠組み。
[停止時引継ぎ](verification/2026-09-12-development-checkpoint.md)にbranch・証拠・保持ファイルを記録した。
古いCI通知だけでは再開せず、ユーザーの新しい方針を先に適用する。

## 文書の読み分け

現在の手順は`docs`直下と`docs/guides`、現在状態はこの文書と台帳を参照する。
`docs/history`、日付付き検証記録、調査スナップショット、過去のrelease notesは履歴であり、
古いsourceの結果を新しいsourceへ自動的に引き継がない。
0.6.0タグ内の文書は出荷時点で固定されているため、公開後の状態説明はmainの文書を参照する。
