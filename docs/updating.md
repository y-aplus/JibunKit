# 基盤を更新する

更新日: 2026-09-12。公開版0.6.0と、その後のmainの区別は[現在状態](status.md)を参照。

この文書は、JibunKit基盤を更新しながら個人用ミニアプリを維持するための境界を示す。現在の構成は動的プラグイン機構を持たず、ミニアプリをSwift Packageへビルド時に組み込む。

## 編集箇所を分ける

個人用ミニアプリの処理、保存形式、Root View、Feature固有の通知予約は独立Packageの`Modules/<Name>/Sources/<Name>Feature`などへ置く。ミニアプリ固有の画面や通知予約処理を`Sources/JibunKit`へ追加しない。通常の追加で基盤と交差する箇所は次に限定する。

| 交差箇所 | 個人用ミニアプリで行う変更 |
| --- | --- |
| `Project.swift` | 独立Packageのpathとapp targetへのproduct依存を追加する |
| `Package.swift` | root PackageへFeatureを置く場合にtarget/productとテスト依存を追加する |
| Integration targetまたはホストの薄い接続ファイル | MiniAppDefinition、保存先・バックアップ・通知操作の接続を定義する |
| `Sources/JibunKit/MiniAppRegistry.swift` | Featureの定義を`all`へ1件列挙する |

通知を使う場合も、ホストの`NotificationAppDelegate`は増やさず、共通payloadから同じdestination mappingへ渡す。必要なOS連携に応じて、Widget/extension、App Shortcuts、[Featureのplist/entitlements宣言](guides/feature-build-requirements.md)と検証対象を追加する。background等の登録はMiniAppDefinitionの`onHostLaunch`へ接続する。詳しくは[ミニアプリの追加](mini-apps.md)を参照する。

基盤側として扱うのは、`JibunKitCore`、root navigation、通知の受け取り口、共有ビルド設定、workflow、共通文書である。個人用の機能処理をこれらへ直接埋め込まない。

## 基盤更新を取り込む前

1. 作業ツリーを確認し、個人用変更を意味のある単位でコミットする。
2. カウンター値、各ミニアプリの保存内容、bundle ID、App Group、現在導入中の版を記録する。実データやTeam IDはGitへ保存しない。
3. 取り込む基盤の変更履歴を読み、保存キー、識別子、最低iOS版、ビルドツールの変更を確認する。
4. `git diff`で、個人用変更と基盤更新が同じ交差箇所へ触れるか確認する。

公開リポジトリを`upstream`、個人用forkを`origin`として使う場合の最小例は次のとおりである。remote名が違う場合は読み替える。

```bash
git status --short
git fetch upstream
git diff HEAD..upstream/main
git merge upstream/main
```

実際のリポジトリでブランチを新設するか、mergeとrebaseのどちらを使うかは、そのリポジトリの規則に従う。この文書の検証のためだけに利用者のブランチやremoteを作らない。

## 競合を解消する

`Package.swift`と`MiniAppRegistry.swift`は、基盤と個人用ミニアプリの両方が触れやすい。単純に`ours`または`theirs`を選ばず、次をすべて残す。

- 基盤側が追加・変更したtargetsと依存。
- 個人用feature targetと本体からの依存。
- 既存と新規の定義、およびID・namespace・通知IDの一意性。
- 各定義の表示名、アイコン、destination。
- 既存のbundle ID、App Group、保存キー。変更が必要なら移行を別タスクとして設計する。

通知payloadの古いIDは未知値として一覧へ戻し、別ミニアプリへ推測で割り当てない。保存形式を変更する場合は、旧値を残すか移行するかを明示し、0.xであることを理由に黙って破棄しない。

## 取り込み後に確認する

1. `swift test`でID衝突、App Group解決、各feature、独立保存を確認する。
2. Tuist／XcodeのビルドでiOS向けコンパイルとWidget入りIPAの整合性を確認する。
3. Shortcutsを含む場合はGitHub ActionsのXcode経路で公式App Intentsメタデータ入りIPAを生成する。
4. 既存アプリを削除せずSideStoreで上書きし、保存値、一覧、各画面、Shortcuts、Widget、通知を確認する。
5. SideStoreで署名更新し、同じ項目を再確認する。

失敗時は、feature処理、iOSビルド、App Intentsメタデータ、SideStore署名、実機動作を分けて原因を探す。ビルド成功だけで保存やsystem surfaceを合格にしない。

## 対応範囲

この更新手順が扱うのは、同じAppleアカウント、bundle ID、App Groupを維持したソース更新と上書きインストールである。Appleアカウント変更、bundle ID変更、App Group変更、削除後の再導入は自動移行の対象ではない。必要になった時点で、データのexport/importまたはキー移行を別仕様として決める。

## 2026-09-07のnamespace修正

組込み済みの`counter`、`reminder`の保存キーと通知IDは変わらない。新たに導入された文字列IDのうち、ドットを含むIDだけは、保存namespaceと通知ID内のドットを`%2E`へ変換する。元のIDと通知payloadは維持する。

未公開ブランチの旧方式でドット入りIDを使った派生がある場合、更新前にバックアップし、該当Featureが所有するキーを明示して旧キーから新キーへ移す。旧方式では他Featureと同じキーになり得るため、基盤は所有者を推測した一括移行・削除をしない。旧通知はそのFeatureが予約したIDを明示して取り消し、新IDで再予約する。
