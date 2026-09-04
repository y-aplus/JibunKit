# Security Policy

## 対応範囲

0.1の公開前は`main`の最新状態だけを対象とします。公開後は、最新の公開releaseと`main`について、可能な範囲で修正を検討します。実験的な個人プロジェクトのため、応答期限や修正版の提供期限は保証しません。

JibunKitのsource、GitHub Actions、生成したIPA、bundle・App Group設定が原因となる問題を対象にします。iOS、Xcode、SideStoreそのものの問題は各提供元へ報告してください。ただし、JibunKit側の使い方や設定により問題が生じる場合は対象です。

## 脆弱性の報告

脆弱性の詳細を公開Issue、Pull request、Discussionへ投稿しないでください。

- リポジトリ公開後は、GitHubの **Security → Report a vulnerability** から[非公開の脆弱性報告](https://github.com/y-aplus/JibunKit/security/advisories/new)を作成してください。
- 非公開期間中にアクセス権を持つ共同作業者は、同じSecurity画面からdraft security advisoryを作成してください。
- 非公開報告の入口が利用できない場合は、公開Issueへ詳細を書かず、「private reporting channelが利用できない」ことだけをIssueで知らせてください。

報告には、影響する版またはcommit、再現条件、期待結果と実際の結果、想定する影響、最小限の再現手順を含めてください。Apple Account情報、2FA、token、署名鍵、証明書、provisioning profile、pairing file、Team ID、UDID、実際のリマインダー内容などは添付しないでください。

## 公開前の安全境界

- GitHub ActionsへAppleの認証情報や個人の署名材料を渡しません。ActionsのIPAはad-hoc署名とし、SideStoreが端末側で最終署名します。
- 外部GitHub Actionはreview済みの固定commitを参照します。
- workflowは追跡済みのcredential・署名・pairing・SDK・IPA候補を検査し、見つけた場合はartifactを生成しません。
- reminder文面はUserDefaultsへ保存され、ローカル通知へ表示されます。秘密情報の保存先としては使用しないでください。

公開手順と最終確認は[docs/releasing.md](docs/releasing.md)を参照してください。
