# P0-A 契約・分担

2026-09-12実装再開。方針baseline main `31e0681474142ec3ab4cc4cc2de3f3f7e40dbe96`。
対象P0-1/3/6、合格条件は[plan.json](plan.json)。本書は実装中の契約で、成功証拠ではない。

## 共通契約

- Featureの非選択/disappearと終了は分離する。起動はownerごとに一回、再開時は新Runtimeを使う。
- 親がCoreのMiniAppFeatureLifetime、Definitionの任意lifetime、通常hostの起動表示/失敗再試行を所有する。
- MiniAppFeatureLifetimeはMainActor。init(id:configure:)で新Runtimeを受け取るasync throwing構成処理を渡す。start() async throws、stop() async、runtimeとstateのread-only状態、restoreLifecycleを提供する。
- 構成失敗は登録済みRuntime資源を終了してから失敗を返す。同時start/stopは同じ遷移を待ち、終了前に次の世代を開始しない。復元による一時停止は、それ以前に起動済みのFeatureだけ再開する。
- Runtimeは既存の取消/全Task完了待ち/逆順cleanupを維持。終了診断はスナップショットで待機段階・残Task/cleanup数・開始時刻を示す。強制終了や期限での成功扱いを追加しない。
- 保存の通常入口は既存RestoreCoordinator.withStoreAccessへ参加。移行/リセットは同じowner予約の排他入口withStoreMaintenance(for:lifecycle:operation:)を使う。lifecycleは任意、Value: Sendableを返せるasync throwing操作。取消は開始前に確認、既に始めたapplyの整合性/rollbackはstoreが所有し、resumeは既存の失敗報告規則を維持。
- RecordsFeatureはCore依存を追加せず、注入可能な通常操作境界でhostへ接続。単独利用の既定動作を維持。snapshot内部で同owner予約を二重取得しない。
- SQLiteはnative SQLiteの既存比較を拡張し、通常書込/移行/リセット/停止復帰でBを保持。万能DB wrapperは作らない。

## 担当とファイル所有

親: MiniAppFeatureLifetimeと専用tests、MiniAppDefinition、host接続、共有manifest/CI、計画・台帳、統合レビュー。
保存担当（既存「JibunKit D02 購読の所有権」スレッド）: RestoreCoordinator/RestoreLifecycleの保守操作、Recordsの全通常保存入口・backup接続、SQLite比較、担当tests/guide。
診断担当（既存「JibunKit通知UI連続実行の検証」スレッド）: Runtime/TaskScope終了診断と専用tests、P0-6局所処理の判断例/guide。
共有manifestが必要なら変更内容を提出し、親がまとめて反映する。担当は別branch/worktreeを使う。

## 一括提出と検証

各担当は実装・接続・失敗試験・既存証拠/未検証範囲をまとめて提出し、個別CIを起動しない。
親は自身の実装と統合した一式をレビューしてから、固定SHAに通常host/shared tests/IPA/UIと生成・対象比較を最大2 runで計画する。
既存試験の再利用はsourceと差分根拠を明記。状態遷移・終了待ち・store競合・破損/移行/リセット・B保持の操作列を初回CI前に確定する。
OS/Swift確認不能なこのWindows環境でローカル成功を捏造せず、Python/tool/静的確認と未実行Swiftを区別する。
実機専用P0-3.deviceは0.7.0候補へまとめる。0.7.0完了時に需要調査結果が未反映ならユーザーへ要求する。
