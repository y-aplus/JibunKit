> 最新公開版: [0.4.0](https://github.com/y-aplus/JibunKit/releases/tag/0.4.0)。1.0は未達で、mainでは幅広いFeatureの非干渉共存を開発中です。

# JibunKit

SideStoreで使う、**自作ミニアプリを束ねるスーパーアプリ**の基盤。

自分の用途に合わせて開発する利用者（ゆる開発者）が、ミニアプリを追加し、使いながら育てられることを目指します。1本のネイティブiOSアプリとして構成し、ミニアプリはビルド時に組み込みます。

## 現在の状態

公開版は[0.4.0](https://github.com/y-aplus/JibunKit/releases/tag/0.4.0)。1.0に向けた開発は継続中です。[0.4.0の変更と検証範囲](release-notes-0.4.0.md)を参照してください。現在のビルドはTuist／Swift PackageとGitHub ActionsのmacOS／Xcode経路を使います。App IntentsメタデータとWidgetを含むIPAを生成します。

独立Featureの雛形・単独実行・ホスト共存、選択バックアップ、添付を含む復旧を実装しています。参照Featureの[Records](Modules/Records/README.md)では、添付の取込み・プレビュー・再起動後保持・削除を2026-09-09の中間実機確認で確認しました。通知と詳細遷移の拡張、最終回帰・出荷確認は継続中です。[1.0の完成条件と残作業](docs/superpowers/plans/2026-09-08-jibunkit-1.0.md)を参照してください。

本体 `com.jibunkit.app`、Widget `com.jibunkit.app.Widget`、App Group `group.com.jibunkit.shared`を維持します。0.1.0公開時の実機実績は[導入・更新](docs/sidestore.md)に記録しています。過去の確認結果を現在の出荷候補の確認済み扱いにはしません。

## 公開版0.1の範囲

- ミニアプリ一覧、カウンターと第2ミニアプリによる追加・共存の実証。
- アプリ再起動、更新インストール、SideStoreでの署名更新後も保たれる保存値。
- ショートカットへの独自操作の登録、数値入力、処理、結果の返却。
- 共有した値を表示するWidgetと、予約・対象ミニアプリへの遷移ができるローカル通知。
- Mac購入を前提にしないビルド・導入手順、ライセンス、追加・更新・貢献・検証の文書。

公開時の完成条件と検証履歴は、以下の0.1設計・作業計画を参照してください。

## 文書

| 文書 | 内容 |
| --- | --- |
| [0.1の設計・完成条件](docs/superpowers/specs/2026-08-28-jibunkit-foundation-design.md) | 製品像、必須機能、対象外、Git・OSS運用 |
| [技術確認](docs/superpowers/specs/2026-08-28-jibunkit-technical-review.md) | 一次資料・公開ソースの確認結果と、実機で確かめること |
| [1.0の目標案と設計原則](docs/superpowers/specs/2026-08-28-jibunkit-1.0-direction.md) | 継続利用の目標、共通基盤への先行投資、将来の検討候補 |
| [0.1の作業計画](docs/superpowers/plans/2026-08-28-jibunkit-0.1.md) | 技術検証から公開までの順序と完成条件の対応 |
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
| [元の検討メモ](personal-swiftui-superapp-plan.md) | ChatGPTが作成した参考資料。現在の仕様は上記の設計文書を優先 |

## 1.0に向けた作業

現在の依頼はJibunKit v1.0の完成。[完成計画](docs/superpowers/plans/2026-09-08-jibunkit-1.0.md)で、独立開発・実用規模の共存・データ復旧・システム連携・出荷の残作業と証拠を管理する。単発のCI成功を1.0完成とは扱わない。

## 現在の開発基盤

TuistとSwift Packageを標準にする。Featureの単独開発・実行と、JibunKitへの薄い接続層を分ける。xtool生成・Ruby後加工・独自Python雛形生成は廃止した。手順は[ビルド](docs/build.md)と[ミニアプリ追加](docs/mini-apps.md)を参照する。0.1.0公開時の実機実績は、Tuist移行後の実機実績とは区別する。

## 開発・導入の前提

無料のAppleアカウントとSideStoreを最低条件にします。Windows上のWSLは単体テストに使い、Shortcutsを含むSideStore向けIPAはGitHub Actionsが提供するmacOS／Xcode環境で作ります。Macの購入は前提にしません。

Shortcuts、本体・Widget間の共有、アプリ単体の再起動後の保存、更新インストール、署名更新後の維持は、旧称・旧識別子の構成で実証済みです。JibunKitとしての確認対象もiPhone 16e／iOS 26.6／SideStore 0.6.3とし、改名後の実機結果は[検証記録](docs/verification/0.1.md)へ追記します。ビルド環境や署名の制約は技術確認文書に記録しています。

個別アプリの移植、コンパイル済みアプリの動的実行、ミニアプリのストアは0.1の対象外です。ソースコードがある独立Swift／SwiftUIアプリをFeatureライブラリと薄いIntegrationへ分離する手順は、[Recordsの接続例](Modules/Records/README.md)で説明しています。画面数や保存方式を固定せず、独立したFeatureのままホストへ接続します。

## 変更の扱い

機能要求・完成条件・明示的な制約を維持し、変更の理由と影響を説明します。0.1を継続して育て、ミニアプリの追加・変更・継続利用を容易にする共通基盤には先行投資します。個別アプリやサンプルの完成を着手条件にせず、目的への効果と複雑さ・保守負担から判断する原則を試行します。

Gitの既定ブランチは`main`です。エージェントによる作業は、作業環境で適用されるグローバルの指示を確認してください。新しい作業ブランチを作成する前に、利用者へ明示します。

リポジトリは公開されています。認証情報、署名鍵、端末の識別情報、実データは、Issueやリポジトリへ投稿しないでください。通常の変更と問題報告は[CONTRIBUTING.md](CONTRIBUTING.md)、脆弱性は[SECURITY.md](SECURITY.md)に従って非公開で報告してください。

## ライセンス

[MIT License](LICENSE)。第三者のtoolやApple SDKには、それぞれの利用・配布条件が適用されます。現在の外部toolと非同梱の境界は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)に記録しています。このリポジトリにApple SDKや署名鍵は含めません。
