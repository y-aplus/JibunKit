# 外部データ identity / CloudKit 接続

## 所有契約

`MiniAppExternalRecordIdentity` は次の全要素を持つ。Feature は `localID` だけを外部保存のキーにしない。

- `MiniAppID`（owner）
- CloudKit container identifier と database scope
- backend が返した account identifier と、その照合ごとに発行する generation
- Feature 内の `localID`

CloudKit adapter は owner ごとに `jibunkit.<owner>` の custom record zone と subscription ID を使う。同じ
`localID` を A/B が使っても zone が異なる。管理から A を削除すると A の zone だけを削除し、B の record、
runtime、非初期値は変更しない。任意 container 間の移行、競合解決、業務データの汎用同期はこの API の範囲外。

## 通常 Feature への接続

署名済み host が container を明示的に生成して adapter へ渡す。

```swift
let container = CKContainer(identifier: "iCloud.com.example.Product")
let backend = CloudKitExternalIdentityBackend(container: container)
let external = MiniAppExternalIdentityFeature(
    id: featureID,
    container: try MiniAppExternalContainer(identifier: "iCloud.com.example.Product"),
    backend: backend
)

MiniAppDefinition(
    id: featureID,
    title: "Example",
    systemImage: "externaldrive",
    lifetime: external.lifetime,
    removal: external.removal
) { context in
    ExampleView(coordinator: external.coordinator)
}
```

`lifetime.start()` は account を照合して subscription を用意する。runtime shutdown は admission を閉じ、
coordinator の account generation を無効化する。管理の disable は既存の lifetime 停止を、データ削除は既存の
`MiniAppRemovalProvider` をそのまま使う。復元後は新しい runtime で再度 `activate()` されるため、停止前の handle は
再利用せず `identity(localID:)` を取り直す。

account change notification を host が受けたときは、該当する各 Feature の
`coordinator.accountDidChange()` を呼ぶ。旧世代の要求は取消を backend に依頼し、取消不能な async CloudKit 呼出しも
完了時の generation 照合で結果を隔離する。旧 handle の read/write/delete は `.staleGeneration` になる。

失敗した activation は runtime 起動失敗として扱われ、既存 `MiniAppFeatureLifetime` の停止完了後に再試行できる。
片方の account/通信失敗を別 owner の停止や削除へ拡大しない。

## CloudKit の前提と診断

実通信には次がすべて必要。

1. Apple Developer portal と署名 profile で iCloud/CloudKit capability が有効。
2. entitlements の container identifier が `MiniAppExternalContainer.identifier` と一致。
3. CloudKit Dashboard に schema/container があり、端末が iCloud account を利用可能。
4. custom zone を利用できる private database（製品で shared database を使う場合は共有契約も別途設計）。

親 host の既存 `FeatureBuildRequirement` 合成には、少なくとも app target の
`com.apple.developer.icloud-container-identifiers = [<container>]` と
`com.apple.developer.icloud-services = ["CloudKit"]` を Feature owner の要求として加える。複数 Feature の同じ
container/services は既存の文字列配列規則で重複除去する。profile にない entitlement を ad-hoc に足しても利用可能には
ならない。診断 host、通常 host、extension は別 target なので、不要な target へ宣言を流用しない。

Core、`P2IdentityProbe`、`UnavailableExternalIdentityBackend` は `CKContainer()` を呼ばない。したがって entitlement のない
診断 host も定義を列挙しただけでは落ちない。native adapter は、上記を満たす host が作成した `CKContainer` の注入を
必須にしている。

`Tests/P2Identity/P2IdentityNativeTests.swift` の実 CloudKit round-trip は、署名済み test host で環境変数
`JIBUNKIT_CLOUDKIT_CONTAINER` を明示した場合だけ実行する。未設定時は skip であり成功ではない。fake backend の
所有・取消・遅着・失敗/復旧試験も、OS 通信成功や Dashboard 設定成功の証拠とは呼ばない。

## 観測すべき結果

- 二 owner が `same-local-id` を保存し、片側削除後も他方を読める。
- account 変更前に開始した遅い応答が `.staleGeneration` になり、新 account の値を上書きしない。
- Feature 停止後の遅着が破棄され、再開時に新 identity を取得する。
- 一時的な account/通信失敗後の再起動で復旧し、他 owner の runtime/data は維持される。
- native round-trip だけは `CKContainer` を介した save/fetch/delete として別に記録する。
