# Third-party notices

JibunKitBackupはZIP archive処理のためZIPFoundation 0.9.20へ依存し、アプリへリンクします。ライセンス本文は`Sources/JibunKitBackup/Resources/ZIPFoundation-LICENSE.txt`としてbundleにも含めます。プロジェクト本体のsourceには[MIT License](LICENSE)が適用されます。

次の表に依存ソフトウェアと外部サービスの用途・同梱範囲を示します。ZIPFoundationを除くツールやサービス本体はIPAへ同梱しません。それぞれの利用・配布条件は提供元の条件が優先します。

| 対象 | 現在の用途 | 条件 |
| --- | --- | --- |
| [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/0.9.20) | JibunKitBackupのZIP作成・読込み。Swift Package依存としてアプリへリンク | [MIT License](https://github.com/weichsel/ZIPFoundation/blob/0.9.20/LICENSE)。ライセンス本文をアプリbundleへ同梱 |
| [Tuist 4.207.0](https://github.com/tuist/tuist) | project・target・template生成 | [MIT License](https://github.com/tuist/tuist/blob/4.207.0/LICENSE.md)。CIでarchiveのSHA-256を固定し、IPAへ同梱しない |
| Apple Xcode 26.6 / iOS SDK | GitHub-hosted runnerとローカルSDK生成元でのbuild | [Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf)。SDK本体は含めない |
| [actions/checkout v6](https://github.com/actions/checkout) | GitHub Actions runnerへsourceをcheckout | [MIT License](https://github.com/actions/checkout/blob/main/LICENSE)。workflowでは固定commitを参照 |
| [actions/upload-artifact v7](https://github.com/actions/upload-artifact) | 検証用IPAをActions artifactとして保存 | [MIT License](https://github.com/actions/upload-artifact/blob/main/LICENSE)。workflowでは固定commitを参照 |
| [SideStore 0.6.3](https://github.com/SideStore/SideStore) | 利用者の端末でIPAを最終署名・導入・署名更新 | [AGPL-3.0 License](https://github.com/SideStore/SideStore/blob/develop/LICENSE)。利用者が別途導入し、JibunKitへ同梱しない |

この一覧は現在のrepositoryと確認済み経路を表します。第三者codeをアプリへ組み込む変更では、採用前にlicense、notice、source提供義務、binary配布条件を確認し、この文書を更新してください。
