# Changelog

このプロジェクトの利用者に影響する変更を記録します。

## [Unreleased]

### Changed

- ミニアプリのID、表示情報、遷移先を1件のDescriptorへ統合し、通常の追加でホストのID enumや画面遷移switchを編集しない登録方式へ変更。
- Featureへ安定した保存・通知namespaceを渡す`MiniAppContext`を追加し、独立アプリの`@main`をFeatureから分離する組み込み境界を明文化。
- カウンターとリマインダーのRoot View・保存処理・通知予約をFeature側へ移し、`MiniAppContext`から保存キーと通知情報を取得する基準実装へ変更。保存キーと通知先は従来通り。
- 1.0の目標候補を、ソースコードがある独立Swift／SwiftUIアプリからFeatureライブラリと薄いAdapterへの分離支援として明確化。

## [0.1.0] - 2026-09-04

### Changed

- 製品名をJibunKitへ変更し、本体・Widget・App Groupの技術識別子も中立なJibunKit名へ統一。

### Added

- ミニアプリ一覧、共有保存を使うカウンター、独立保存を使うリマインダー。
- App Shortcutsから数値を加算し、更新値を返すApp Intent。
- 3サイズの表示専用Widget。
- 許可操作、予約、foreground表示、通知タップからの遷移を扱うローカル通知。
- WSLでのローカル確認、GitHub ActionsのXcode 26.6によるIPA生成、SideStore導入・更新の文書。
- ミニアプリ追加、基盤更新、貢献、脆弱性報告、公開・releaseの手順。

### Verified

- iPhone 16e、iOS 26.6、SideStore 0.6.3で、JibunKitの初回導入、build 2への上書き、署名更新後の保存値・Shortcuts・Widget・通知を確認。
- クリーンなGitHub-hosted macOS runnerで、全テスト、App Intentsメタデータ、本体・Widget、署名構造、IPA整合性を確認。

### Security

- GitHub Actionsの外部actionを固定commitへ変更し、checkout credentialを保持しないようにした。
- credential、署名・pairing材料、Apple SDK、IPAを追跡しない公開境界チェックを追加した。

### Fixed

- App Shortcutからの加算が整数範囲を超える場合、processを停止せず保存値を維持してerrorを返すようにした。

[Unreleased]: https://github.com/y-aplus/JibunKit/compare/0.1.0...HEAD
[0.1.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.1.0
