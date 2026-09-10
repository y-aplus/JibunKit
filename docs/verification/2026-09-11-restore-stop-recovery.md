# D07 復元前の停止失敗と回復

状態: 実装済み、CI待ち。DB終了失敗を検出した後、既に終了したRuntimeをそのまま残す問題を対象とする。

`MiniAppRestoreLifecycle`へ任意の`recoverAfterFailedStop`を追加した。停止失敗時だけ回復を待ち、applyと通常resumeは呼ばない。回復成功でも復元は失敗として返す。回復失敗は元の停止理由と合わせて保持し、`stopAndRecovery`を共有バックアップ画面で区別する。既存callback未指定時の契約は維持する。

## 検証内容

- 共有unit: 回復成功/失敗、二つの失敗理由、後続owner非実行、正常停止後に回復callbackを呼ばないこと。
- coordinator: 回復を意図的に保留し、取消後も同ownerのsnapshotを拒否すること、他ownerは進むこと、回復完了後の予約解放。
- native SQLite: statementを保持して実際のBUSY closeを起こし、Runtime終了後の回復で元のDBを保持。新Runtime経由でAへ再書込みでき、BのRuntimeとDBも利用可能であること。
- CI専用二Feature host: 既存4経路に停止途中の失敗と回復失敗を加えた計6経路。共有BackupScreenの説明、未復元値、回復後の新Task受付、Bの値と実行継続を確認する。

WindowsではSwift/iOS試験を実行できないため、diff検査とCI selector検査を行い、macOS共有試験・生成hostの選択UI試験・通常host回帰・IPA検査をCIへ依頼する。

source `35324f0`のCIは[34502469319](https://github.com/y-aplus/JibunKit/actions/runs/34502469319)で実行中。生成hostは`MigrationUITests/GeneratedFeatureUITests/testRestoreFailuresDescribeDataAndRuntimeStateWithoutChangingOtherFeature`、通常hostは`MigrationUITests/MigrationUITests/testMiniAppSearchFiltersAndOpensResults`を指定した。先行34502431856は通常hostのmethod名を誤指定したため取り消した。訂正後の二selectorはローカルの存在検査を通した。完了はgh run watchからcodex queueへ通知する。

## 責任と限界

callbackはFeatureが実装する。途中まで閉じた複数接続、外部writer、通常書込みや購読の受付を共有Runtimeが発見・自動修復するものではない。回復callbackが取消で失敗した場合も回復失敗として扱う。DB以外の移行/リセット、別process排他、D07全体は未完。CI専用probeは通常IPAへ含めない。
