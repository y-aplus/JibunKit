# ZaikoのFeature分離メモ

更新日: 2026-09-05

独立ZaikoApp(`IOSapp/zaikoIOSapp`、3ファイル計1777行)をJibunKitの3つ目のFeatureへ分離した記録。1.0目標候補「独立SwiftアプリのFeature化支援」の最初の実例。

## 分離点

- Feature側へ移したもの: `InventoryDomain`・モデル・バックアップ互換処理(`ZaikoDomain.swift`、FoundationのみでLinuxテスト可)、`ZaikoStore`・`InventoryBackupDocument`(`ZaikoStore.swift`)、`ContentView`派生の`ZaikoRootView`。`fileImporter`/`fileExporter`や設定画面遷移はView層の機能としてそのまま動く。
- App Shellに残るもの: `@main`と単独版の`NotificationAppDelegate`(foreground表示のみ)。ホスト側delegateは`[.banner, .list, .sound]`で表示し、tapは登録ID検証を経て遷移する。

## 基盤側の判断

- 保存: `UserDefaults.standard`+固定キーから、App Group suite(`MiniAppStorage`)とContext名前空間(`zaiko.state`/`zaiko.backup.latest`/`zaiko.backup.prev`)へ。JibunKit内では新規キーであり、単独版からの移行はJSON export/importで行う。JSON形式自体は不変でPWA互換を保つ。
- 通知: アイテム毎の複数予約型のため、単一request ID想定にはそのまま乗らない。request IDを`jibunkit.zaiko.notification.<itemID>`のprefix運用とし、各通知へ`MiniAppContext.notificationUserInfo`を付加してtap遷移を解決する。古い`zaiko.alert.` prefixの通知はJibunKit側の整理対象外(単独版の領域であり共有しない)。
- 2026-09-07に`ZaikoRootView`の最外層`NavigationStack`を除去し、JibunKitが持つstackを利用する構成へ変更した。設定・編集・補充のsheetは各sheet内でstackを持つ。単独版で再利用する場合はApp Shell側でRoot Viewをstackに包む。
- ついでに直したもの: `DateCoding`の共有`ISO8601DateFormatter`を都度生成へ(Swift 6の`MutableGlobalVariable`エラー対応)。

## 検証

- `swift test`: 全28テスト成功。
- `xtool dev build --ipa`: 成功。`#Preview`マクロはxtool環境にないため含めない(既存Featureと同様)。
- `unzip -t`: errorなし。
- 実機検証は保留。§10.3相当として次の実機時に確認する: 一覧からの起動、保存の独立、通知tapからの在庫管理遷移、上書き・署名更新後の維持。

## web版との整合(2026-09-05)

web版(PWA)の修正に合わせ、次を同一仕様へ揃えた。

- 編集フォームの初期在庫は開いた時点の残量(負は0止め、未確定は空)。`updateItem`は日時リセットと対になる。
- フォーム初期値(在庫・速度)は桁区切りなしの素朴な書式。表示側のグループ化は維持。
- 停止再開の補正は`resumedAt - max(pauseStartedAt, lastPurchased)`へ一律化。停止中の追加・編集・補充分も補正対象。
- 未対応だった通知オフ→オン時の予約喪失は、web版で実装できないためSwift側で対応した。予約記録はpending実態と突合せて有効とし、再有効化で再予約される。判定は`InventoryDomain.shouldSkipReschedule`に切り出してLinuxテストする。web版は未修正のまま。

## 2026-09-07のレビュー修正

Zaikoは移植の試験例として残す。基盤の先行設計・実装を許可するための必須サンプルではなく、JibunKitがFeature固有の不具合を吸収する対象でもない。

- バックアップ形式の判定・全件検証をFoundationのみの`ZaikoBackup`へ分離した。不正な項目を黙って除去せず、全体を失敗として扱う。version 3の不正なデータを旧形式として再解釈しない。旧形式では名前・在庫量が必要で、未知の版・重複ID・範囲外ID・不正な日付を拒否する。空在庫はversion付きenvelopeで受け付け、由来を判定できない空の裸配列は拒否する。通常のPWA v3（ネイティブ通知項目なし）は合成fixtureで検証する。
- 通知記録は配信後も保持する。通知オフ・全体停止で取り消したpending予約の記録だけを除去し、再有効化・再開で再予約する。停止中の日時補正は新しい補充サイクルに数えない。複数の予約更新は直列に処理し、途中で状態が変わった場合は最新状態で再計算する。
- 識別子と排他処理はJibunKitCoreが担当し、在庫形式・補充サイクル・通知する条件はZaikoFeatureが担当する。

検証結果は[レビュー修正の検証記録](../../verification/2026-09-07-review-fixes.md)を参照。過去のWSL検証と今回のActions検証は区別する。

## 実機前の操作確認

移植元の画面・データ処理・App entry pointと照合し、[実機前の移植確認](../../verification/2026-09-07-zaiko-migration.md)へ機能ごとの対応と検証結果を記録する。実機で確認できるという理由だけで、シミュレーターや自動テストで検証できる項目を未実施のまま渡さない。
