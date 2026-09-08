# Records参照Feature

複数画面・構造化データ・添付を持つ独立Swift Package。JibunKitCoreへ依存せず、単独AppとJibunKitで同じFeatureを使用する。製品Registryへの自動登録はしない。

## 現在の機能

記録の作成・編集・検索・詳細・削除確認、添付のFiles取込み・Quick Look表示・削除、作成日時、ファイル単位snapshot、旧schemaからの移行を実装している。編集は保存までドラフトに留める。

RecordStoreはversion付きJSON indexとUUID名の添付を、呼出側が指定したディレクトリへ保存する。同じ保存先には1つのstore actorを使う。別actor・別プロセスの同時更新は保証しない。添付名を保存pathに使わない。indexはatomic write、添付削除はindex確定後に行い、後片付け失敗で未参照ファイルが残る場合がある。

## 単独で開発する

macOSでは`swift test --package-path Modules/Records`で保存処理を検証する。`tuist generate --path Modules/Records --no-open`でRecordsExample workspaceを生成し、RecordsExample schemeで実行する。Example/App.swiftがNavigationStackとApplication Supportの保存先を供給する。

WindowsからはGitHub Actionsを利用する。`feature_validation=true`で独立版・生成Featureのビルド、さらに`simulator_tests=true`で独立起動とホスト共存のUI回帰まで実行する。[CIの実行モード](../../docs/verification/2026-09-08-ci-structure.md)を参照。

## 既存アプリを分離して組み込む

1. 画面・業務ロジック・保存実装をFeature Packageへ置く。既存の画面数や画面内の型をホストに合わせて削らない。@main、署名、entitlements、Info.plistはApp Shellに残す。
2. 保存先などApp固有の依存を初期化引数にする。RecordsではRecordStore(directory:)が境界であり、Feature内部から共有App Groupを解決しない。
3. 元のApp Shellから同じFeatureを呼べる状態を保つ。元のデータ形式・ID・添付名の対応も保持し、保存先を変えただけでデータ移行が完了したとは扱わない。
4. Integration/RecordsMiniApp.swiftとRecordsBackup.swiftをホストsourceへ含める。Project.swiftのpackagesへ`.package(path: "Modules/Records")`、JibunKit-Appの依存へ`.package(product: "RecordsFeature")`を追加し、RegistryへRecordsMiniApp.definitionを列挙する。
5. IntegrationがMiniAppFilesのrecords領域と単一store actorを所有する。初期化に失敗したらエラーを表示し、別保存先へ黙って切り替えない。FeatureのUUID詳細遷移はホストのNavigationPathがそのまま扱う。
6. 単独版・ホスト版それぞれの保存と起動、再起動後の詳細、他Featureの保存維持を確認する。単独版からホスト版への既存データは明示的なsnapshot移行で扱う。App間で保存先が自動共有されるわけではない。

TMAの固定target数は要求しない。RecordsのPackageはFeatureとテストだけで、JibunKit依存の接続は外にある。この分離は既存アプリの不具合を基盤が補償する仕組みではない。

## バックアップと更新

exportSnapshot(to:)は参照添付とindexを新しいディレクトリへコピーする。validateSnapshot(at:)はライブ保存先へ触れずに内容を検証する。restoreSnapshot(from:)は全ファイルをstagingへコピーした後に保存先を置換する。上書き確認とsnapshotの寿命管理は呼出側の責任。

RecordsBackup.providerはこれをMiniAppDefinition.fileBackupへ接続する。ホストのバックアップ画面はfile providerを含む選択をZIPとして保存する。既存JSONの読込みは維持され、Feature間の一括rollbackは保証しない。[検証とフォーマット](../../docs/verification/2026-09-08-file-backup.md)を参照。

現行index/file provider schemaは2。schema 1には作成日時がないためnil（画面では不明）として読み、日時を推測しない。読込みだけでは元ファイルを書き換えず、正常な編集保存・snapshot出力/復元でschema 2へ移る。旧ID・本文・添付を保持する。未来のschemaを拒否し、破損を空データとして上書きしない。新しいsnapshotを旧版Recordsへ戻す互換性は提供しない。

## 検証範囲と残る制限

- 単独編集・再起動・ホストのUUID詳細遷移・Counter値維持はCIで確認済み。
- snapshot/ZIPの選択復元、旧JSON共存、128 MiBの添付全内容維持を確認済み。メモリ測定はmacOSのプロセス最大RSSでありiOS実機の容量保証ではない。
- schema 1からの読込み・復元・編集後移行と未来schemaの保存維持は34221667275で成功。
- 共通バックアップ画面のZIP Files往復は34218612906で成功。
- Records自身の添付取込み・Quick Look・削除の一連のUI操作と、作成日時追加後のUI回帰は別途確認が必要。
- 大量レコードのDB効率、複数プロセス協調、独立Appとホスト間の自動データ転送は提供しない。
