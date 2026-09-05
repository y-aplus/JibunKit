# ZaikoのFeature分離メモ

更新日: 2026-09-05

独立ZaikoApp(`IOSapp/zaikoIOSapp`、3ファイル計1777行)をJibunKitの3つ目のFeatureへ分離した記録。1.0目標候補「独立SwiftアプリのFeature化支援」の最初の実例。

## 分離点

- Feature側へ移したもの: `InventoryDomain`・モデル・バックアップ互換処理(`ZaikoDomain.swift`、FoundationのみでLinuxテスト可)、`ZaikoStore`・`InventoryBackupDocument`(`ZaikoStore.swift`)、`ContentView`派生の`ZaikoRootView`。`fileImporter`/`fileExporter`や設定画面遷移はView層の機能としてそのまま動く。
- App Shellに残るもの: `@main`と単独版の`NotificationAppDelegate`(foreground表示のみ)。ホスト側delegateは`[.banner, .sound]`で表示し、tapは登録ID検証を経て遷移する。

## 基盤側の判断

- 保存: `UserDefaults.standard`+固定キーから、App Group suite(`MiniAppStorage`)とContext名前空間(`zaiko.state`/`zaiko.backup.latest`/`zaiko.backup.prev`)へ。JibunKit内では新規キーであり、単独版からの移行はJSON export/importで行う。JSON形式自体は不変でPWA互換を保つ。
- 通知: アイテム毎の複数予約型のため、単一request ID想定にはそのまま乗らない。request IDを`jibunkit.zaiko.notification.<itemID>`のprefix運用とし、各通知へ`MiniAppContext.notificationUserInfo`を付加してtap遷移を解決する。古い`zaiko.alert.` prefixの通知はJibunKit側の整理対象外(単独版の領域であり共有しない)。
- `ZaikoRootView`は単独版 parity のため自前の`NavigationStack`を保持する。ホストのstackとの二重化は既知の負債であり、実機確認時に見直す。
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
- 未対応: 通知オフ→オン時の予約喪失(web版も未修正)。両側で残件とする。
