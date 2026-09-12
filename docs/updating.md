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

## 二つの独立Packageの片側だけを更新する

例として`Modules/FeatureA`と`Modules/FeatureB`を独立Swift Packageとして維持し、Aだけを互換更新する。両Packageに同名の`Config.json`や同じ翻訳keyがあっても、各targetでresourcesを宣言し`Bundle.module`から読む。片方のresourceをhostの`Bundle.main`へ移したり、BのファイルをAの更新commitへ含めたりしない。

更新前にA/B双方の固定点を作る。

1. 作業ツリーをcleanにし、AとBをそれぞれPackage単独でtestする。
2. 生成hostでA/BのFeature ID、同名resourceの実値、英語・日本語等の翻訳、保存値を記録する。秘密値は記録しない。
3. A/BのID、library product名、保存namespaceを記録し、更新前状態をcommitする。
4. 保存形式を変更するAは、現行版でAだけのbackupを作る。Bや共有UserDefaults suite全体のcopyをAのbackup代わりにしない。

Aの互換更新は`Modules/FeatureA`と必要なA Integrationだけにまとめる。既存IDと保存先を維持し、追加フィールドは旧データをdecodeできるoptional/defaultまたは明示的schema移行として導入する。読取り時に破損を空データへ置き換えず、移行・リセットは[保存アクセスの調停](guides/store-access-coordination.md)を使う。Recordsのversion 1から2へのdecode・検証・明示移行が小さい実例である。長寿命TaskやDB接続を持つAは[Feature lifetime](guides/feature-lifetime.md)と[Runtime／復元接続](runtime-restore-integration.md)も更新する。BのID、Package manifest、resource、保存処理は変更しない。

更新後は次を順に確認する。

```bash
swift test --package-path Modules/FeatureA
swift test --package-path Modules/FeatureB
tuist generate --no-open
tuist build JibunKit-App
```

その後、生成hostをビルドしてA/Bの定義が両方Registryへ残ることを確認する。更新インストールでは、Aの旧保存値を新コードが読み移行できること、Aの新フィールドが保存・再読込できること、A/Bそれぞれの同名resourceと翻訳が元のPackageから表示されること、Bの保存値が更新前と同じことを実画面で確認する。Package test、host build、実画面の保存・resource比較は別の結果として記録する。

### 壊れたA更新から復旧する

AのPackage test、Tuist生成、host compile、旧データdecode、resource比較のいずれかが失敗したら配布へ進まない。エラーがpath/product/target依存/Registryなら[追加時の診断表](mini-apps.md#package接続に失敗したとき)の該当箇所を直す。Aの更新を一つのcommitへ分離していれば、未配布の壊れた更新は`git revert <Aの更新commit>`で履歴を残して戻し、A/BのPackage testとhost生成を再実行できる。未commitの作業を先に退避せず、広いディレクトリへ`git restore`を実行しない。

既に端末上でAのschema移行が始まった場合、コードだけを戻して旧版が新schemaを読めると仮定しない。まずA所有データを保全し、旧schemaも読めるforward fixを優先する。確認済みbackupへ戻す必要がある場合は、利用者確認後にAのproviderだけを選択復元し、Bを選択しない。復旧後もAの再読込とBの値・resource保持を再確認する。Package全体、App Group、UserDefaults suiteを推測で削除しない。

P0-Bの同意・無効化・削除・提示は候補`codex/p0-b-management`から今後統合する範囲であり、現行公開版の更新手順として完了扱いしない。統合後の接続・復旧判断は[Feature管理](guides/feature-management.md)、[利用同意](guides/feature-consent.md)、[所有データ削除](guides/feature-data-removal.md)、[Feature所有の提示](guides/feature-owned-presentations.md)に従う。削除済み状態や同意をbackup復元だけで暗黙に有効化しない。

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
