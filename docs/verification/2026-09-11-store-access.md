# D07 通常の保存操作と復元の受付調停

状態: 実装済み、CI待ち。

既存coordinatorの排他的な復元/snapshot予約と、Featureごとの通常アクセス件数を組み合わせた。`withStoreAccess`は通常アクセス同士を直列化せず、復元/snapshotとの交差だけをConflictにする。既存providerを使うhostは、登録された通常操作がある場合も変更前に拒否し、データ使用中と表示する。

## 検証

- 同ownerの二通常アクセスが重なり、片方だけ終了しても復元不可、全件終了後に復元可。他ownerは進む。
- 排他的復元中の通常アクセスを受付前に拒否し、他ownerは進む。
- 例外/取消/不正IDの受付と解放。取消だけで処理中の予約を外さない。
- native SQLiteのWAL transactionを保持し、別接続ではcommit前の値が見える間、同ownerの復元とsnapshotを拒否。Bの書込みは継続し、A commit後に復元可能。
- 二Featureの生成host: A/B両方の通常書込みを保持→共有BackupScreenでA復元拒否→A書込み完了→A復元成功→新RuntimeでA書込み→Bは未変更で継続/完了。

Windowsではdiff/selectorの検査を行う。Swift/macOS・iOS UI・IPAはCIで確認する。通常画面の回帰とRecordsの既存試験を合わせ、選択外UIや実機を検証済みとしない。

source `2aecc3f`を[34506390553](https://github.com/y-aplus/JibunKit/actions/runs/34506390553)へ送った。生成hostは`MigrationUITests/GeneratedFeatureUITests/testOrdinaryStoreAccessBlocksRestoreUntilFinishedAndPreservesOtherOwner`、通常hostは`MigrationUITests/MigrationUITests/testMiniAppSearchFiltersAndOpensResults`。両selectorの存在検査とdiff検査が成功。gh run watchとcodex queueで完了時に再開する。

## 残る範囲

opt-inの協調契約であり、通常書込みの全自動検出、DBのtransaction自体の排他、別process writerは対象外。通常アクセスが0件でもDB接続が閉じているとは限らず、restoreLifecycleの停止・再開責任を維持する。D07全体は未完。
