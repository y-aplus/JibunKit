# 1.0の互換性とFeatureの責任境界

更新日: 2026-09-12。公開版0.6.0と、その後のmainの区別は[現在状態](status.md)を参照。
0.7.0出荷候補のP0はCIと一括実機を確認済み。直前公開版0.6.0との区分・配布状態は[出荷記録](verification/2026-09-13-0.7-release.md)を参照。

1.0に向けた実装・レビューで守る基準。現時点で1.0を公開済みという意味ではない。
[Issue #5の版境界](implementation-priorities.md)に従い、P0完了を0.7.0、P0を維持したP1完了を0.8.0とする。
途中のpatch版にも機能追加・検証の進捗を含められるが、互換性破壊を版番号だけで正当化しない。
API/データ変更は版にかかわらず移行・失敗時の保持・利用者への説明を必要とする。
1.0の最終対応範囲は需要調査後に決める。minorごとに[現状文書の全件確認](ci-boundaries.md#マイナー版の文書・出荷gate)を行う。

## 共存に対する基盤の責任

> JibunKitへ統合した結果、独立アプリならOSやアプリ境界によって得られていた隔離・調停・所有権管理が失われるなら、その差分をJibunKitが可能な範囲で補う。

Featureの分離や共通APIの提供だけでこの責任を満たしたとはしない。独立アプリの境界で得られた効果が統合後も保たれるか、競合・取消・終了・復帰で検証する。技術的制約と未対応の判定は[共存基準](coexistence-boundaries.md)に従う。

## 維持する識別子と保存データ

Feature IDは表示名と独立した永続識別子である。表示名を変えてもIDを変えない。既存Counter/ReminderのID、保存キー、従来の通知request IDは維持する。IDや保存先を変更する必要がある場合は、旧データからの移行と途中失敗時の復旧方法を実装し、更新インストールで検証する。

MiniAppContextによるnamespaceは共存のための整理であり、Feature間のセキュリティ隔離ではない。Featureのコードは同じプロセスと署名権限で動く。他Featureの保存値を読まない・変更しない責任はFeatureにもある。

## 依存してよい接続

- MiniAppDefinitionとRegistryへの列挙をホスト接続とする。Feature固有の分岐を一覧やAppNavigationへ追加しない。
- 独立FeatureはCoreへの依存を選べる。Coreを使わないFeatureにはIntegrationから保存先・サービス・入口を渡す。
- 公開のMiniAppID、MiniAppContext、保存API、バックアップprovider、URL生成を使う。ホスト内の画面型、検証用アプリ、CI内の一時的なファイル変換は公開APIとしない。
- 新しい機能は原則として追加APIや任意登録で提供する。公開APIの削除・引数変更が必要なら移行例と非推奨期間を検討し、互換性を破る変更を無言で入れない。

## バックアップの互換性

外側のJibunKitBackup/version 1と各entryのschemaVersionは別の版である。新しい保存形式・ファイルベースのバックアップ経路を追加しても、既存version 1の読込みを維持する。未知の版を既知の版として推測して読み込まない。

Featureはpayloadの形式・schema移行・整合性検証・保存処理を所有する。prepareではライブデータや通知を変更しない。旧schemaを受け入れる場合は変換した状態を検証してから適用操作を返す。破損データで部分的な状態を作って成功として返さない。

全Featureの原子的復元は保証しない。適用済み・失敗対象・未実行を利用者へ区別して伝える。失敗したFeature内のrollbackやDB transactionはFeatureの実装に従う。ファイルをコピーするだけで開いたDBの整合したsnapshotが取れるとは扱わない。

## システム連携

通知の予約条件・再予約・取り消しはFeatureの責任とし、CoreはIDと遷移先の共存を支援する。Widget/App Intents/権限・entitlementsはAppまたはextensionの接続層で宣言する。Featureを追加しただけで必要な権限やextensionが自動的に有効になるとは説明しない。

現在のjibunkit://mini-app/<ID>は入口を開くだけで、データ変更や任意操作を実行しない。任意のdestination queryによる詳細接続でも既存の入口URLを維持する。詳細識別子の検証とnavigation valueへの変換はIntegrationが所有し、ホストはFeature別の型を解釈しない。未知のURLを別Featureへ推測で転送しない。

## 変更時の確認

公開API・保存形式を変更する作業では、旧版データの読込み、単独版とホスト版のビルド、他Featureとの独立性、該当するUI経路を確認する。出荷候補は同じsourceから作ったIPAで上書き・署名更新を確認する。Foundation/Simulatorの成功を署名環境の実績として代用しない。
