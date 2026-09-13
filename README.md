> 0.7.0 build8出荷候補のP0全6単位をCIと2026-09-13の一括実機確認で検証済み。正式公開前の安定版は0.6.0。P1/0.8.0は未完了、1.0の範囲は需要調査後に決定する。

# JibunKit

SideStoreで使う、**自作ミニアプリを束ねるスーパーアプリ**の基盤。

自分の用途に合わせて開発する利用者（ゆる開発者）が、ミニアプリを追加し、使いながら育てられることを目指します。1本のネイティブiOSアプリとして構成し、ミニアプリはビルド時に組み込みます。

## 現在の状態

公開版は[0.6.0](https://github.com/y-aplus/JibunKit/releases/tag/0.6.0)。公開版とmainの差分・開発状態は[現在状態](docs/status.md)にまとめています。[0.6.0の変更と検証範囲](release-notes-0.6.0.md)を参照してください。現在のビルドはTuist／Swift PackageとGitHub ActionsのmacOS／Xcode経路を使います。App IntentsメタデータとWidgetを含むIPAを生成します。

独立Featureの雛形・単独実行・ホスト共存、選択バックアップ、添付を含む復旧を実装しています。参照Featureの[Records](Modules/Records/README.md)では、添付の取込み・プレビュー・再起動後保持・削除を2026-09-09の中間実機確認で確認しました。0.6.0の通常UI11件・Files経由のJSON選択復元とIPA検査は成功済みです。P0の出荷候補は0.7.0、次のP1完了は0.8.0とします。1.0の最終対応範囲は需要調査後に決めます。[優先実装と版の到達条件](docs/implementation-priorities.md)、[統合差分台帳](docs/coexistence-ledger.md)を参照してください。

本体 `com.jibunkit.app`、Widget `com.jibunkit.app.Widget`、App Group `group.com.jibunkit.shared`を維持します。0.1.0公開時の実機実績は[導入・更新](docs/sidestore.md)に記録しています。過去の確認結果を現在の出荷候補の確認済み扱いにはしません。

## 公開版0.6.0とmain

通常IPAはCounterとReminderを含みます。独立Featureの組込み、選択JSON・添付ZIPバックアップ、
通知・URL・Widget・Shortcutsの接続に加え、共有background refreshの永続要求/調停/復旧APIと
Package翻訳のmixed localizationを提供します。静的Package Widgetのgallery・描画・他owner保持も検証済みです。

公開後のmainにはSDKのmodule alias比較、shared refresh実機用診断fixture、P0-Aの寿命・保存・終了診断、P0-Bの管理・同意・提示を追加しました。P0-A/P0-Bは通常・生成CIの非実機条件を確認済みです。
SDKはiOSで公開product名を分けるmanifest編集が必要です。refreshの実OS受付・起動・期限は未検証です。
これらを0.6.0配布物へ含めたとは扱いません。[版別の状態と証拠](docs/status.md)を参照してください。

0.7.0候補は[CI34705653297](https://github.com/y-aplus/JibunKit/actions/runs/34705653297)と[実機の一括確認](docs/verification/2026-09-13-0.7-device-check.md)を完了しました。[出荷記録](docs/verification/2026-09-13-0.7-release.md)で配布状態を区別します。

## 文書

| 文書 | 内容 |
| --- | --- |
| [公開版とmainの現在状態](docs/status.md) | 0.6.0の出荷範囲、未リリース差分、開発状態 |
| [共存の補完責任](docs/coexistence-boundaries.md) | 技術的な責任と未対応/不能の判定規則 |
| [優先実装と版の到達条件](docs/implementation-priorities.md) | P0/P1、0.7/0.8境界と1.0の決定手順 |
| [大きなCI単位の運用](docs/ci-boundaries.md) | 事前契約、証拠gate、minorごとの文書確認 |
| [統合差分台帳](docs/coexistence-ledger.md) | 各領域の現在の実装・検証・残作業 |
| [1.0完成計画](docs/superpowers/plans/2026-09-08-jibunkit-1.0.md) | 到達点と再開後の作業の枠組み |
| [履歴: 0.1の設計・完成条件](docs/superpowers/specs/2026-08-28-jibunkit-foundation-design.md) | 製品像、必須機能、対象外、Git・OSS運用 |
| [履歴: 初期技術確認](docs/superpowers/specs/2026-08-28-jibunkit-technical-review.md) | 一次資料・公開ソースの確認結果と、実機で確かめること |
| [履歴: 1.0の目標案と設計原則](docs/superpowers/specs/2026-08-28-jibunkit-1.0-direction.md) | 継続利用の目標、共通基盤への先行投資、将来の検討候補 |
| [履歴: 0.1の作業計画](docs/superpowers/plans/2026-08-28-jibunkit-0.1.md) | 技術検証から公開までの順序と完成条件の対応 |
| [ビルド手順](docs/build.md) | Tuistによるローカル開発とGitHub ActionsによるIPA生成 |
| [SideStore導入・更新](docs/sidestore.md) | IPAの導入、上書き、署名更新、確認済み条件と保証境界 |
| [ミニアプリの追加](docs/mini-apps.md) | feature、画面、通知、Widget、App Intentを追加する手順と検証境界 |
| [ミニアプリ組み込み簡素化の設計](docs/superpowers/specs/2026-09-04-mini-app-integration-simplification.md) | 0.1時点のRegistry、Context、互換性、受入条件、外部エージェントへの引継ぎ |
| [互換性方針](docs/compatibility.md) | 公開API、保存識別子、バックアップschema、Featureの責任境界 |
| [基盤の更新](docs/updating.md) | 個人用ミニアプリとの編集境界、更新取り込み、競合解消後の検証 |
| [貢献手順](CONTRIBUTING.md) | 変更の範囲、確認方法、通常の問題報告、Pull request |
| [Security Policy](SECURITY.md) | 脆弱性の非公開報告と公開前の安全境界 |
| [変更履歴](CHANGELOG.md) | 利用者に影響する変更とrelease状態 |
| [第三者notice](THIRD_PARTY_NOTICES.md) | 外部tool・SDK・導入toolの条件と非同梱の境界 |
| [通信状態の接続](docs/network-integration.md) | Feature/profile別Cookie・HTTP認証・cacheと終了待ち |
| [Runtimeと復元](docs/runtime-restore-integration.md) | タスク停止・非同期解放・選択復元の接続 |
| [Sceneと画面状態](docs/scene-navigation.md) | window別navigationと通知先の選択 |
| [公開・release](docs/releasing.md) | 公開前check、tag、公開切替、release後の対応確認 |
| [元の検討メモ](personal-swiftui-superapp-plan.md) | ChatGPTが作成した参考資料。現在の判定は共存の完成基準と統合差分台帳を優先 |

## 1.0に向けた作業

目標はJibunKit v1.0の完成です。Issue #5のP0はCI・実機確認を完了し、0.7.0を出荷準備中。次はP1の通常OS入口・通知・HTTP/Webを0.8.0へ進めます。需要調査[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)を受領し、1.0推奨境界の正式採用を確認中です。[完成基準](docs/coexistence-boundaries.md)と[台帳](docs/coexistence-ledger.md)を維持し、0.7/0.8の公開を1.0完成と扱いません。

## 現在の開発基盤

TuistとSwift Packageを標準にする。Featureの単独開発・実行と、JibunKitへの薄い接続層を分ける。xtool生成・Ruby後加工・独自Python雛形生成は廃止した。手順は[ビルド](docs/build.md)と[ミニアプリ追加](docs/mini-apps.md)を参照する。0.1.0公開時の実機実績は、Tuist移行後の実機実績とは区別する。

## 開発・導入の前提

無料のAppleアカウントとSideStoreを最低条件にします。Windows上のWSLは単体テストに使い、Shortcutsを含むSideStore向けIPAはGitHub Actionsが提供するmacOS／Xcode環境で作ります。Macの購入は前提にしません。

実機確認の履歴は[導入・更新](docs/sidestore.md)、配布物ごとの確認範囲は[0.6.0公開記録](docs/verification/2026-09-12-0.6-release.md)を参照してください。過去の実機成功を0.6.0や現在のmainそのものの実機成功へ読み替えません。

既存アプリの無修正移植、コンパイル済みIPAの動的実行、ミニアプリストアは提供しません。ソースのあるSwift／SwiftUIアプリをFeatureと薄いIntegrationへ分離する手順は[Recordsの接続例](Modules/Records/README.md)で説明しています。画面数や保存方式を固定せず、必要な共有資源の補完は台帳で追跡します。

## 変更の扱い

機能要求・完成条件・明示的な制約を維持し、変更の理由と影響を説明します。ミニアプリ基盤を継続して育て、ミニアプリの追加・変更・継続利用を容易にする共通基盤には先行投資します。個別アプリやサンプルの完成を着手条件にせず、目的への効果と複雑さ・保守負担から判断する原則に従います。

Gitの既定ブランチは`main`です。エージェントによる作業は、作業環境で適用されるグローバルの指示を確認してください。新しい作業ブランチを作成する前に、利用者へ明示します。

リポジトリは公開されています。認証情報、署名鍵、端末の識別情報、実データは、Issueやリポジトリへ投稿しないでください。通常の変更と問題報告は[CONTRIBUTING.md](CONTRIBUTING.md)、脆弱性は[SECURITY.md](SECURITY.md)に従って非公開で報告してください。

## ライセンス

[MIT License](LICENSE)。第三者のtoolやApple SDKには、それぞれの利用・配布条件が適用されます。現在の外部toolと非同梱の境界は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)に記録しています。このリポジトリにApple SDKや署名鍵は含めません。
