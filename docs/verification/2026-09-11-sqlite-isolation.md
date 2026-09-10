# D06 native SQLiteによる保存先の比較検証

状態: macOS native SQLiteの3試験成功。既存MiniAppFilesの検証であり、製品DB wrapperは追加しない。

`MiniAppSQLiteIsolationTests`はnative SQLite3を直接使う。二Featureに同じ`store.sqlite`を開き、WALを有効化して同名tableへ別の値を保存する。WALファイルの存在、複数接続での読戻し、A接続終了/専用ディレクトリ削除/再作成、Bの書込み継続と再接続保持を確認する。

第二の試験はSQLite Backup APIでWAL内のcommitも含むsnapshotを作り、Aを変更後に戻す間もBの新しい値が保たれることを確認する。第三はstatementを保持して`sqlite3_close`をBUSYにし、閉鎖失敗後も接続が生きていることと、statement解放後にcloseできることを確認する。任意ファイルコピーを安全なDBバックアップと仮定しないための比較である。

WindowsではSwift/SQLite3 Swift moduleを実行できないためdiff検査のみ。CI [34500952925](https://github.com/y-aplus/JibunKit/actions/runs/34500952925)（source `71f08ce`）は成功。macOSの共有134試験が失敗0で終了し、SQLiteのsnapshot/復元は0.031秒、BUSY closeは0.025秒、同名DB/再接続/削除は0.020秒で成功した。通常iOSビルドとIPA検査も成功。UI変更はなく、Simulatorは起動していない。

## 残る検証と実装

SQLiteの同一processの実ファイル操作であり、別process writer、iOS Data Protection、GRDB/Core Data/SwiftData、DBごとの移行と復元adapter、故障・電源断の耐性までは証明しない。特にRuntimeのcleanup hookだけではDB終了エラーをhostへ伝えないため、throwingな復元stop adapterで検査する必要がある。D06/D07全体の完了にはしない。
