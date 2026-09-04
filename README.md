# JibunKit

SideStoreで使う、**自作ミニアプリを束ねるスーパーアプリ**の基盤。

自分の用途に合わせて開発する利用者（ゆる開発者）が、ミニアプリを追加し、使いながら育てられることを目指します。1本のネイティブiOSアプリとして構成し、ミニアプリはビルド時に組み込みます。

## 現在の状態

**0.1の公開準備中です。** 製品名をJibunKitへ変更し、本体`com.jibunkit.app`、Widget `com.jibunkit.app.Widget`、App Group `group.com.jibunkit.shared`へ技術識別子も変更しました。Windows上のWSLでは全11テストとJibunKit名のWidget入りIPA生成に成功しています。Shortcuts登録に必要な公式App Intentsメタデータは、GitHub ActionsのmacOS／Xcode 26.6経路で生成します。

旧称・旧識別子のビルドでは、iPhone 16e／iOS 26.6／SideStore 0.6.3上でF1〜F7を確認済みです。ただしJibunKitは別のアプリ識別子を持つため、その結果を現在の版へそのまま引き継ぎません。改名後のActionsビルド、初回導入、カウンター、Shortcuts、3サイズのWidget、リマインダー通知、上書き更新、署名更新を再確認してから最終候補とします。現在のIPAはまだ配布・導入対象として認定したリリース成果物ではありません。**0.1の完成・リリースに合わせてOSS公開し、それまでは非公開**とします。

## 0.1で届けるもの

- ミニアプリ一覧、カウンターと第2ミニアプリによる追加・共存の実証。
- アプリ再起動、更新インストール、SideStoreでの署名更新後も保たれる保存値。
- ショートカットへの独自操作の登録、数値入力、処理、結果の返却。
- 共有した値を表示するWidgetと、予約・対象ミニアプリへの遷移ができるローカル通知。
- Mac購入を前提にしないビルド・導入手順、ライセンス、追加・更新・貢献・検証の文書。

これは完成条件であり、動作実績ではありません。0.1は設計文書の**F1〜F7・O1〜O4の全11項目**を満たして完成とします。文書をGitHubへ保存したことだけでは0.1の完成にはなりません。

## 文書

| 文書 | 内容 |
| --- | --- |
| [0.1の設計・完成条件](docs/superpowers/specs/2026-08-28-jibunkit-foundation-design.md) | 製品像、必須機能、対象外、Git・OSS運用 |
| [技術確認](docs/superpowers/specs/2026-08-28-jibunkit-technical-review.md) | 一次資料・公開ソースの確認結果と、実機で確かめること |
| [1.0の目標案と設計原則](docs/superpowers/specs/2026-08-28-jibunkit-1.0-direction.md) | 継続利用の目標、YAGNI、将来の検討候補 |
| [0.1の作業計画](docs/superpowers/plans/2026-08-28-jibunkit-0.1.md) | 技術検証から公開までの順序と完成条件の対応 |
| [ビルド手順](docs/build.md) | WSLでのローカル確認とGitHub ActionsによるSideStore向けIPA生成 |
| [SideStore導入・更新](docs/sidestore.md) | IPAの導入、上書き、署名更新、確認済み条件と保証境界 |
| [ミニアプリの追加](docs/mini-apps.md) | feature、画面、通知、Widget、App Intentを追加する手順と検証境界 |
| [基盤の更新](docs/updating.md) | 個人用ミニアプリとの編集境界、更新取り込み、競合解消後の検証 |
| [貢献手順](CONTRIBUTING.md) | 変更の範囲、確認方法、通常の問題報告、Pull request |
| [Security Policy](SECURITY.md) | 脆弱性の非公開報告と公開前の安全境界 |
| [変更履歴](CHANGELOG.md) | 利用者に影響する変更とrelease状態 |
| [第三者notice](THIRD_PARTY_NOTICES.md) | 外部tool・SDK・導入toolの条件と非同梱の境界 |
| [公開・release](docs/releasing.md) | 公開前check、tag、公開切替、release後の対応確認 |
| [元の検討メモ](personal-swiftui-superapp-plan.md) | ChatGPTが作成した参考資料。現在の仕様は上記の設計文書を優先 |

## 開発・導入の前提

無料のAppleアカウントとSideStoreを最低条件にします。Windows上のWSLは単体テストと補助的なiOS buildに使い、Shortcutsを含むSideStore向けIPAはGitHub Actionsが提供するmacOS／Xcode環境で作ります。Macの購入は前提にしません。

Shortcuts、本体・Widget間の共有、アプリ単体の再起動後の保存、更新インストール、署名更新後の維持は、旧称・旧識別子の構成で実証済みです。JibunKitとしての確認対象もiPhone 16e／iOS 26.6／SideStore 0.6.3とし、改名後の実機結果は[検証記録](docs/verification/0.1.md)へ追記します。ビルド環境や署名の制約は技術確認文書に記録しています。

個別アプリの移植、任意の既存IPAの実行、ミニアプリのストアは0.1の対象外です。IPA向けアダプタ・変換器は将来の検討候補であり、実現方式や提供時期は決まっていません。

## 変更の扱い

機能要求・完成条件・明示的な制約を維持し、変更の理由と影響を説明します。0.1を1.0へ育てる方向性とYAGNIは、具体的な技術判断に用いる指針です。

Gitの既定ブランチは`main`です。エージェントによる作業は[AGENTS.md](AGENTS.md)を確認してください。新しい作業ブランチを作成する前に、利用者へ明示します。

現在は非公開リポジトリ内で公開準備を行う段階です。非公開であっても、認証情報、署名鍵、端末の識別情報、実データは、Issueやリポジトリへ投稿しないでください。通常の変更と問題報告は[CONTRIBUTING.md](CONTRIBUTING.md)、脆弱性は[SECURITY.md](SECURITY.md)に従ってください。

## ライセンス

[MIT License](LICENSE)。第三者のtoolやApple SDKには、それぞれの利用・配布条件が適用されます。現在の外部toolと非同梱の境界は[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)に記録しています。このリポジトリにApple SDKや署名鍵は含めません。
