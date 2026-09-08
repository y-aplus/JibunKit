# Records参照Feature

1.0の実用規模Feature検証を進めるための独立Swift Package。製品Registryへ自動登録しない。JibunKitCoreへ依存せず、App Shellから保存先を受け取る。

現在は記録の作成・編集・削除と添付ファイルの追加・読込み・削除を実装。構造化データはversion付きJSON、添付ファイルはUUID名の別ファイルとして保存する。添付の表示名を保存先pathに使わない。記録indexはatomic writeで置換し、添付追加はファイル作成後にindexへ登録する。削除はindexのcommit後に不要ファイルを整理する。整理失敗時には参照されないファイルが残る可能性がある。

同じ保存先は1つのRecordStore actorで扱う。別プロセス・別actorによる同時更新を保証しない。大量データのDBとしての効率、ファイルベースsnapshot、旧schema移行は後続の検証・実装範囲。現時点で1.0の実用Feature条件を完了とはしない。

次に一覧・詳細・編集画面、単独App Shell、ホストIntegration、バックアップとschema移行を接続する。個々の処理のテストは `swift test --package-path Modules/Records` で実行する。

## 保存処理の検証と画面接続

CI 34182293224（source f88020c）は成功。Recordsの保存・添付・再読込み・別保存先の独立性・不正編集・破損index・実際の添付書込み失敗を含むテストが通った。

RecordsRootViewへ一覧・本文を含む検索・詳細・新規作成・編集・削除確認を接続した。編集は保存までドラフトに留め、キャンセルで保存値を変更しない。単独RecordsExampleがNavigationStackとApplication Supportの保存先を供給する。製品Registryへは未登録。UIテストは作成、編集キャンセル、保存、再起動、検索、削除キャンセルと確定を通す。CIで独立iOSビルドとUIテストを実行する。

添付ファイルはこの段階では名前表示まで。追加・プレビュー・削除の画面操作、ホストIntegration、バックアップ・schema移行は引き続き未完了。

CI 34182637204（source 924d559）はRecords UIの編集結果比較で失敗した。TextEditorへのタップ後、入力カーソルが先頭にあり、実際の編集内容は ` editedOriginal body` だった。再起動後もその値は維持されていた。末尾追記を前提にした期待値を除き、編集欄で元の本文・追加文字列・キャンセル文字列の不在を確認したうえで、保存後と再起動後に編集欄と同じ内容になることを比較する。製品コードは変更しない。その他の作成・キャンセル・検索・削除操作には、このrunで追加の失敗は報告されていない。

CI 34183544808（source cec44bb）は全step成功。Recordsの作成・編集キャンセル・編集内容保存・再起動・検索・削除確認が通った。

添付のUIを追加した。Filesから通常ファイルを選んで取り込み、Quick Look用の独立コピーを作って表示し、確認後に削除する。取り込みと表示用コピーはFileManagerのファイルコピーを使い、全量Data読込みを行わない。Security-scopedアクセスは取り込み完了まで維持する。Quick Lookへライブの保存ファイルを渡さず、表示終了時に一時コピーを整理する。クラッシュ等で残った一時コピーはOSの一時領域に留まる。

テストへ外部ファイルの取り込み、元ファイル変更後の独立性、表示用コピー変更後の保存内容維持、拡張子保持、ディレクトリ拒否を追加した。添付UIのFiles受渡し・Quick Look表示・削除操作はまだ実行結果を得ていないため、APIテストやiOSビルドだけで完了としない。

CI 34184927254（source 232d7fb）は成功。ファイルコピーによる取り込みとプレビュー用コピーの独立性を含む保存テスト、独立iOSビルド、既存編集UI回帰が通った。添付UIの実操作はこの成功からは推定しない。

## JibunKitへの接続

`Integration/RecordsMiniApp.swift`が薄いホスト接続例。ルートProjectのpackagesへ`.package(path: "Modules/Records")`、JibunKit-Appの依存へ`.package(product: "RecordsFeature")`を追加し、この接続ファイルをホストsourceへ含め、Registryへ`RecordsMiniApp.definition`を列挙する。単独PackageにはIntegrationを含めない。

単独版は自身のApplication Support、ホスト版はMiniAppFilesのrecords領域を使用する。接続層が保存先と単一store actorを所有し、Feature内は変更しない。保存先を開けない場合に別の場所へ黙って保存しない。単独版からホスト版へ既存データを自動転送する機能はまだない。バックアップ経由の移行は次段階で接続する。

CIの一時構成にだけRecordsを登録し、作成・再起動後の詳細読込み・Counter保存値の維持を追加検証する。通常の製品Registryは変更しない。
