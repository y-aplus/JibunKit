# Zaiko移植の実機前確認

## 対象

移植元: [y-aplus/zaikoIOSapp](https://github.com/y-aplus/zaikoIOSapp/tree/f8d47a463d124bf294fe9276e70aa1fdd1fe71fb)、commit `f8d47a463d124bf294fe9276e70aa1fdd1fe71fb`。README、`ZaikoApp/App/ContentView.swift`、`ZaikoStore.swift`、`ZaikoApp.swift`、Info.plistを照合した。

ここでの完成判断は、この独立iOS版の主要機能をJibunKitへ組み込むことが対象。JibunKit 1.0全体の完成や、あらゆるFeatureを無修正で受け入れることは意味しない。

## ソースの対応

| 移植元 | JibunKit側の対応 |
| --- | --- |
| ContentViewと各sheet | ZaikoRootView.swift。一覧・カード・設定・編集・補充・ファイル入出力を保持。最外層stackはホストへ移管 |
| モデル・消費計算・表示変換 | ZaikoDomain.swift。既存の編集時残量・停止期間補正の修正も維持 |
| ZaikoStore | ZaikoStore.swift。保存namespace・通知payloadをContextへ接続 |
| JSON codec・旧形式移行 | ZaikoBackup.swift。全件検証後に適用。不正データの黙った切捨てを廃止 |
| Appのstore所有 | ZaikoRootViewのStateObjectでFeature滞在中のStoreを所有。保存値は再入場・再起動後に再読込み |
| NotificationAppDelegate | JibunKitの単一delegate。banner/list/soundを維持し、登録IDで通知タップを転送 |
| @main・bundle ID・単独版icon・単独配布workflow | JibunKitのApp Shell・識別子・配布経路へ置換。独立アプリを二重に起動する仕組みは持ち込まない |

単独版のUserDefaultsコンテナーは別アプリの領域なので自動読込みしない。データ移行の入口は既存のJSON export/importである。これは移植漏れではなくアプリ境界に伴う移行方法。

## 検証項目

| 項目 | 実機前の確認方法 |
| --- | --- |
| 一覧から起動・一覧へ戻る・タイトル | UIテストで1つのnavigation barと戻る操作を確認 |
| 追加・編集・削除・削除キャンセル | UIテストで保存後の表示と再起動後の維持を確認 |
| 補充 | UIテストと、在庫量・学習後消費速度・ID保持のロジックテスト |
| カテゴリー | UIテストで選択・全件への復帰を確認 |
| 2種類の消費速度入力・残日数・アラート順 | ロジックテスト |
| 全体停止・再開 | UIテストと、停止中変更・日時補正・通知履歴のロジックテスト |
| バックアップ | 形式・正常往復・旧形式・PWA形式・不正形式のロジックテスト。UIでFilesへの保存・読込み画面の起動まで確認。保存JSONの実体も確認。Files経由の復元は下記OSエラーで未確認 |
| 通知 | payloadの登録ID検証、予約履歴・取消し・配信済みサイクルをロジックテスト。foreground表示指定を移植元と照合。UIテストで通知許可・配信・タップ後のFeature遷移 |
| 保存先の独立・同時更新 | 共通suiteのテスト、複数CounterStoreの並行テスト、UIでCounterとZaiko・Reminderを併用 |
| ビルド・配布構造 | Release arm64本体・Widget・App Intentsメタデータ・署名・ZIP構造をActionsで検査 |

## 実行結果

最終対象はcommit `9087bf4582d2b7a42a7d635c9417fe0da2a4b2ab`、[Actions run 34102220630](https://github.com/y-aplus/JibunKit/actions/runs/34102220630)。

- Foundationテスト45件、Release本体・Widget・App Intentsメタデータ・署名構造・IPA検査は合格。
- `testMigrationOperationsAndHostIntegration`は合格（225.227秒）。追加・入力検証・カテゴリー・補充・編集・停止／再開・Feature間の移動・再起動後の保存・削除キャンセル／削除・Reminderの保存を確認した。
- `testNotificationDeliveryAndRouting`は合格（33.619秒）。通知許可・実配信・別Featureからホームへ移った後の通知タップ・Reminderへの遷移を確認した。
- `testZBackupRoundTrip`は失敗。書出しとファイル一覧表示は成功したが、選択したファイルをOSがアプリへ渡せない。したがってrun全体はfailureであり、全UIテスト合格とは扱わない。
- シミュレーターから回収した`zaiko_backup_20260907.json`はversion 3、在庫`Backup Rice`、数量10を含む有効なJSON。読込み選択時にFile Providerが`-1005`（参照先を解決できない）、その内側でresolverが`-1012`を返し、DocumentManagerが空のURL配列を報告している。iOS 26.2と26.5の両方で再現し、JSONデコードへ届く前に止まる。
- 最終runの再起動後の在庫画面と通知遷移後の画面を目視確認した。

移植元との照合と、この環境で実行できる通常操作の確認は完了。既知のアプリ側修正は反映済み。この時点で残っていたFiles経由の復元は、下記の利用者による実機確認で成功した。環境の失敗をアプリ側の自動補正やテストの黙ったskipで隠さない。

### 実機確認用IPA

同runの`JibunKit-ad-hoc` artifact。取得したIPAもZIP整合性、本体・Widgetのbundle ID、0.1.0／build 2を再検査した。

- サイズ: 430,937 bytes
- SHA-256: `bdcad7c00694ad71190aeea1bcc057edec59b68ab1d52c2376262e16383c22b6`
- Actions成果物は保存期限7日。実行ログ・画面・OS診断・保存JSONは`JibunKit-simulator-evidence`にある。実機合格済みreleaseとしては扱わない。


途中のrun `34090521399`で通知タップ時の実クラッシュを検出。クラッシュ記録の`NotificationAppDelegate.userNotificationCenter(_:didReceive:)`生成thunkから`UIApplication._updateSnapshotAndStateRestorationWithAction`へ進む経路がcooperative executor上で実行され、`NSAssertionHandler`からSIGABRTになっていた。async delegateの自動変換に任せず、completion handler形式で画面遷移と完了通知をMainActorへ固定した。修正後のrun `34091719986`と`34092713986`で通知許可・配信・タップ後のFeature遷移テストが合格。

ファイル操作は設定sheetから開き、キャンセル・完了時に設定へ戻る構成へ変更した。ファイル操作失敗は設定上で表示する。

## 利用者による実機確認（2026-09-07）

対象は[確認用プレリリースのIPA](https://github.com/y-aplus/JibunKit/releases/download/zaiko-device-check-20260907/JibunKit.ipa)。上記runのIPAと同一SHA-256。

- ダウンロードしたIPAで、旧バックアップの読込みに成功したとの報告を受けた。シミュレーターのFile Providerエラーで未確認だった移行経路を実機で確認できた。
- 読込み後に多数の通知が届いたとの報告を受けた。通知の実配信は確認済み。古いバックアップ内の在庫が通知条件を満たしていたためか、重複配信があったかは未確認であり、通知スケジュール全体の合格とは扱わない。
- 旧アプリとのUI差で左上を押し間違えることがあるが、現状は許容との判断を受けた。この報告だけを理由にナビゲーションを変更しない。
- 今回の報告には機種・OS・SideStore版の再確認は含まれていないため、過去の検証環境から推定しない。

## 残る実機確認

以下は今回の報告では確認できていない。

- SideStoreで上書き・署名更新した後の保存値、共有Widget、Shortcutsの登録・実行。
- 実端末の通知許可・拒否・集中モード等と、foreground／終了状態からの通知タップ。
- 通知が大量に届いた原因と、同じ在庫サイクルで不要な再通知がないこと。
