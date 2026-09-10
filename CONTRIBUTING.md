# JibunKitへの貢献

JibunKitは、SideStoreで使う個人向けミニアプリ基盤を、小さく保ちながら育てる実験的なプロジェクトです。変更は現在の設計と完成条件に直接つながる範囲へ絞ってください。

## 変更を始める前に

- 現在の仕様は、READMEから参照している設計文書を優先します。元の検討メモは参考資料です。
- 通常の不具合や提案は[GitHub Issues](https://github.com/y-aplus/JibunKit/issues)へ送ってください。脆弱性は公開Issueへ書かず、[SECURITY.md](SECURITY.md)に従ってください。
- 大きな仕様変更は、実装前にIssueで完成条件、利用者への影響、代案を確認してください。
- 認証情報、Apple Account情報、署名鍵、証明書、provisioning profile、SideStore pairing file、Team ID、端末識別子、実データ、Apple SDKを投稿しないでください。

## 実装の原則

- ミニアプリ固有の処理はfeatureへ置き、共通基盤の変更を必要最小限にします。
- 複雑な独立Featureを制約なく接続する目的に必要なら、共通接続の先行実装を認めます。目的・責任境界・検証方法を説明し、サンプルが未作成という理由だけで必要な基盤を保留しません。Feature固有の不具合を基盤で肩代わりすることとは区別します。
- 統合差分台帳を複数エージェントで進める場合は、[台帳実装の並列運用](docs/parallel-implementation.md)に従います。最大3並列とし、常時3実装を維持するのではなく、実装・検証・統合のボトルネックに応じて枠を再配置します。
- テストは仕様と不具合の再発防止に使います。テスト駆動の手順自体を目的にはしません。
- 保存キー、bundle ID、App Group、App Intent、Widget、通知routeの変更は、既存利用者の更新・署名更新後の継続性へ影響するものとして扱います。

## 確認方法

SwiftのあるmacOS／Linux／WSLで次を実行できます。WindowsではActionsを使えます。Apple frameworkに依存するテストとiOSビルドはmacOS／XcodeのCIで確認します。

```bash
swift test
```

iOS本体、App Intent、Widget、通知、plist、entitlements、workflowへ影響する変更は、maintainerが[GitHub Actionsの確定経路](docs/build.md)を実行します。Actionsの成功は実機検証の代わりではありません。SideStoreでの導入・更新やsystem surfaceの確認が必要な変更は、対象端末・OS・SideStore版と操作結果を別に記録します。

文書だけの変更でも、リンク、記載したコマンド、実際の構成との一致を確認してください。

## Pull request

1. forkまたは作業用branchで、1つの目的に絞って変更します。
2. 変更理由、仕様への影響、実行した確認、未確認の範囲を説明します。
3. 必要な文書と変更履歴を同じPull requestで更新します。
4. 秘密情報や生成物を含めていないことを確認します。

互換性を壊す変更や、実機でしか確かめられない変更は、その事実を明示してください。maintainerは設計との一致、最小性、自動チェック、必要な実機結果を分けて審査します。
