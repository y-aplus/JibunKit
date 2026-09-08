# Records参照Feature

1.0の実用規模Feature検証を進めるための独立Swift Package。製品Registryへ自動登録しない。JibunKitCoreへ依存せず、App Shellから保存先を受け取る。

現在は記録の作成・編集・削除と添付ファイルの追加・読込み・削除を実装。構造化データはversion付きJSON、添付ファイルはUUID名の別ファイルとして保存する。添付の表示名を保存先pathに使わない。記録indexはatomic writeで置換し、添付追加はファイル作成後にindexへ登録する。削除はindexのcommit後に不要ファイルを整理する。整理失敗時には参照されないファイルが残る可能性がある。

同じ保存先は1つのRecordStore actorで扱う。別プロセス・別actorによる同時更新を保証しない。大量データのDBとしての効率、ファイルベースsnapshot、旧schema移行は後続の検証・実装範囲。現時点で1.0の実用Feature条件を完了とはしない。

次に一覧・詳細・編集画面、単独App Shell、ホストIntegration、バックアップとschema移行を接続する。個々の処理のテストは `swift test --package-path Modules/Records` で実行する。
