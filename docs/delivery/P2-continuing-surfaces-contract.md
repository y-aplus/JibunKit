# P2-L: Live Activities / AlarmKit の実装境界

2026-09-16開始。0.8.1公開後の製品baselineは88ab7cb、文書/公開照合済みmainは4af35e5。次の0.8.2目標はP2-5（D28）の通常範囲。まだ実装・署名条件・実OS検証が完了したわけではない。

## 最初に揃える責任

Featureは活動の属性/表示/業務状態、アラームの意味・予定と操作内容を持つ。基盤はowner別の操作権限、OS登録との対応、再起動照合、管理/復元時の後始末と他Feature保持を補う。既存MiniAppID/Context・Intents・管理・Runtimeを再利用し、汎用タイマー/通知業務モデルへFeatureを押し込めない。

- appが非選択/背景になっただけではOS上の継続活動を終了しない。Runtimeの画面内Task寿命とOS活動の寿命を混同しない。
- 開始/更新/停止の入力はowner、Feature local ID、必要な世代/OS identifier、Feature所有payload。別owner/不明ID/削除前世代を推測で配送しない。
- 開始失敗/権限拒否/保存失敗/取消は成功扱いせず、Aの失敗でBを更新・削除しない。OS登録と保存の途中終了で再接続可能な範囲を説明する。
- cold launch後は既存OS登録と保存を照合し、二重登録やownerの取り違えを避ける。OSが終了したものを無条件に復活させない。
- 無効化/削除では新規受付を止め、当該ownerのOS活動と更新購読を片付ける。管理完了をOS解除前に表示しない。OS失敗は既存管理の未完了/再試行へ接続する。
- 復元で古い操作が新しい業務データを変更しない。保存値の復元とアラームの再登録/通知発火は別の判断であり、暗黙に期限切れ予定を大量再発火しない。
- 共通CoreはActivityAttributes/AlarmMetadata等の任意Feature型をhost内switchで列挙しない。必要な登録は標準型とFeature側adapter、optional接続で提供する。

## 分担と初回提出

最大3レーン。親はCoreの共通契約、MiniAppDefinition/Registry/Runtime/管理/復元、Project/Package/CI、最終ガイドと実機/出荷を所有する。実装前のnative API/署名条件と契約確認を二つのCLI sol/lowワーカーで並行する。権限/sandbox設定を上書きせず、サブエージェントやChat機能へ変更しない。

- Live Activitiesレーン: `docs/delivery/P2-live-activity-design.md`のみ所有。ActivityKitの型、request/update/endとactivityUpdates/state、cold reconnect、interactive Intents配送、OS上限/拒否、plist/entitlement/署名条件を一次資料と既存コードで整理する。API案とA/B検証fixture/通常host接続案を一括提出する。
- AlarmKitレーン: `docs/delivery/P2-alarm-design.md`のみ所有。schedule/update/stop/cancel、authorization/metadata/Intents、永続OS照合、管理と復元、OS/署名条件を同じ粒度で整理する。API案とA/B検証fixture/通常host接続案を一括提出する。
- 初回は設計と最小native呼出し例を文書へ提出。製品コード/共有ファイル/CI/pushは変更しない。Windowsで実行していないSwift/Xcodeを検証済みにしない。未確認の有料登録制限を事実として扱わない。

二提出を受けて親が共通契約とAPI/担当pathを一度固定し、独立実装を同じbaselineへ渡す。ネイティブ動作の違いが判明する前に共通abstractionや管理APIを別々に実装しない。子ごとのCIは回さない。設計phaseを実装完了とは扱わない。

## CIと実機

P2-L初回実装予算2run。初回の同一sourceで独立/統合native build・metadata、共有owner/復旧試験と通常接続をまとめる。各job見込み25分以内、上限30分目標。実際の入力/filter/再利用sourceと準備/upload込み見積りは提出統合後・投入前に固定する。必要なら二native jobを同じrun内で並列化。署名条件を含む最小native比較を先行する必要がある場合も予算を記録し、実装/CIの分散投入で回数を隠さない。

実機は開始/更新/終了、二ownerの同時利用、OS上の操作配送、アプリ/端末再起動、片側拒否/取消/無効化/削除、通常版への復帰と既存データ保持を一括する。採用する署名/OS構成で動かない箇所は、同条件の独立アプリ比較とAPI/署名根拠を示し、複雑だから未実装という理由と区別する。3失敗までに切り分け、待機はOS通知に任せる。
