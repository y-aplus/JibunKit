# P2-I external identity 提出

- 基点: `7347b483936e7f8bfe45d36984c32390cdcae2b3`
- 実装 commit: `a5bf420f52f29efda3a8b804f9bb58efd3e96e8a`
- branch: `codex/p2-identity`

## 変更契約

- container/account/data の完全な identity を `owner + container identifier/database + account identifier/generation + localID`
  とした。同じ local ID の二 owner は別 custom zone、別 record ID、別 subscription ID になる。
- coordinator は account 変更、Feature 停止、再開ごとに旧 generation を無効化する。取消不能な遅着応答も await 後の
  generation 照合で `.staleGeneration` とし、新 account の結果として公開しない。
- `MiniAppExternalIdentityFeature` が既存 `MiniAppFeatureLifetime` と `MiniAppRemovalProvider` へ接続する。片側停止・削除は
  当該 coordinator/zone だけを対象にし、他 owner の runtime と値を変更しない。
- native adapter は CloudKit 標準の `CKContainer`、private `CKDatabase`、custom `CKRecordZone.ID`、
  `CKRecord.ID`、`CKRecordZoneSubscription` を使う。任意 container 移行、shared/public database の共有設計、競合解決、
  汎用 sync engine は実装していない。
- native adapter は署名済み host が明示生成した `CKContainer` の注入を必須とする。Core、通常の Probe 定義、
  unavailable backend は `CKContainer()` を呼ばないため、entitlement なしの診断 host を定義生成だけで落とさない。
- fake backend の成功と実 CloudKit 通信成功を分離した。実通信試験は署名済み host と
  `JIBUNKIT_CLOUDKIT_CONTAINER` がある場合だけ実行し、未設定は skip とする。

## ソースと試験

- Core: `Sources/JibunKitCore/ExternalIdentity/`
- unit: `Tests/JibunKitCoreTests/ExternalIdentity/MiniAppExternalIdentityCoordinatorTests.swift`
  - 二 owner の同名 record、片側削除/B保持
  - account 変更と旧 handle 拒否
  - account 変更/停止後の遅着隔離
  - activation 失敗からの復旧と B 保持
  - 通常 Feature lifetime の A 停止/再開と B runtime・値保持
- native fixture: `Tests/P2Identity/P2IdentityProbe.swift` は二つの `MiniAppDefinition` と、署名 host 用 backend factory を公開。
- native tests: `Tests/P2Identity/P2IdentityNativeTests.swift` は所有、削除、account 変更、遅着、失敗/復旧を実 Feature/backend
  接続で検証し、明示構成時だけ実 CloudKit save/fetch/delete を行う。
- guide: `docs/guides/external-data-identity.md`

## 検証結果と未実行

- `git diff --cached --check`: 成功（実装 commit 前）。
- 所有 path 照合: 対象 7 file は指定された Core/tests/guide path 内。host、`Project.swift`、workflow、共通台帳、
  元の `C:/Dev/JibunKit`、ignored Zaiko は未変更。
- `swift test --filter MiniAppExternalIdentityCoordinatorTests`: **未実行**。この Windows host に `swift` executable がなく、
  PowerShell が command-not-found で終了した。試験失敗や成功として扱わない。
- Xcode/iOS build、native fixture、署名 CloudKit round-trip: **未実行**。親が source 統合後にまとめて実行する契約のため、
  CI dispatch は行っていない。
- fake backend 試験ソースは実 OS 通信の証拠ではない。実 CloudKit 成功は上記 opt-in native test の実行結果だけで判定する。

## 親 host への必要接続

1. 診断 target に `Tests/P2Identity/P2IdentityProbe.swift` と `P2IdentityNativeTests.swift` を追加し、既存方式で二 definition を
   registry へ合成する。entitlement なしの host は `P2IdentityProbe.definitions`（unavailable backend）を使う。
2. 署名 native host だけが `CKContainer(identifier:)` を生成し、`CloudKitExternalIdentityBackend(container:)` を作り、
   `P2IdentityProbe.features(backend:)` の返す Feature を保持して各 `.definition` を registry へ渡す。
3. 既存 `FeatureBuildRequirement` 合成へ app target の
   `com.apple.developer.icloud-container-identifiers = [<container>]` と
   `com.apple.developer.icloud-services = ["CloudKit"]` を追加する。profile/capability と一致しない ad-hoc 宣言を成功扱いしない。
4. `CKAccountChanged` を受けた host 境界から、保持した各 Feature の `service.coordinator.accountDidChange()` を呼ぶ。
   管理 disable/delete/restore は definition の既存 lifetime/removal 接続を使う。
5. private database custom zone の実 schema/container/account を用意し、環境変数を明示した署名 test host で native round-trip
   を実行する。未設定 skip、fake 成功、host 起動成功だけを CloudKit 通信成功と記録しない。
