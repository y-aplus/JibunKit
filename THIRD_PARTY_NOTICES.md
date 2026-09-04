# Third-party notices

JibunKitのSwift packageは外部packageへ依存しておらず、現在のアプリbundleへ第三者のsourceやbinaryを組み込んでいません。プロジェクト本体のsourceには[MIT License](LICENSE)が適用されます。

次のソフトウェアとサービスは、ビルド、検査、導入のために外部で使用します。リポジトリやIPAには再配布しません。それぞれの利用・配布条件は提供元の条件が優先します。

| 対象 | 現在の用途 | 条件 |
| --- | --- | --- |
| Apple Xcode 26.6 / iOS SDK | GitHub-hosted runnerとローカルSDK生成元でのbuild | [Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf)。SDK本体は含めない |
| [xtool 1.17.0](https://github.com/xtool-org/xtool) | Swift packageからXcode workspaceとIPAを生成 | [MIT License](https://github.com/xtool-org/xtool/blob/main/LICENSE.md)。downloadしたarchiveは固定digestで検査し、IPAへ同梱しない |
| [actions/checkout v6](https://github.com/actions/checkout) | GitHub Actions runnerへsourceをcheckout | [MIT License](https://github.com/actions/checkout/blob/main/LICENSE)。workflowでは固定commitを参照 |
| [actions/upload-artifact v7](https://github.com/actions/upload-artifact) | 検証用IPAをActions artifactとして保存 | [MIT License](https://github.com/actions/upload-artifact/blob/main/LICENSE)。workflowでは固定commitを参照 |
| [SideStore 0.6.3](https://github.com/SideStore/SideStore) | 利用者の端末でIPAを最終署名・導入・署名更新 | [AGPL-3.0 License](https://github.com/SideStore/SideStore/blob/develop/LICENSE)。利用者が別途導入し、JibunKitへ同梱しない |

この一覧は現在のrepositoryと確認済み経路を表します。第三者codeをアプリへ組み込む変更では、採用前にlicense、notice、source提供義務、binary配布条件を確認し、この文書を更新してください。
