# スーパーアプリ基盤 0.1 Implementation Plan

> **For agentic workers:** Use `superpowers:executing-plans` to execute this plan task-by-task. Track execution with the checkboxes below. Read the linked specification and technical review before execution.

**Goal:** SideStoreで利用する、ミニアプリを追加して育てられるスーパーアプリ基盤0.1を、F1〜F7・O1〜O4をすべて満たして届ける。

**Architecture:** スーパーアプリ本体が一覧・画面遷移・外部からの入口を担い、各ミニアプリが画面・処理・保存形式を持つ。画面とショートカットは同じ更新処理を使い、Widgetは共有された表示用データを読む。0.1で必要な分離に留め、将来用の拡張機構は作らない。

**Tech Stack:** Swift／SwiftUI、App Intents、WidgetKit、UserNotifications、Swift Package Managerを中心とする構成案。Windows上のWSLとxtoolを先に検証し、不成立の場合だけGitHub Actionsが提供するクラウド上のmacOS環境を利用する。

**Spec:** [0.1の設計・完成条件](../specs/2026-08-28-appbaseios-foundation-design.md)、[技術確認](../specs/2026-08-28-appbaseios-technical-review.md)、[1.0の目標案と設計原則](../specs/2026-08-28-appbaseios-1.0-direction.md)

**状態:** 実行中。工程1の製品最小構成を実装し、WSL上で単体テストと、App Intent型・Widget extensionを含むIPA生成に成功した。IPAにApp IntentsメタデータがないためF2のローカル経路は不成立と判定した。GitHub Actions上のmacOS経路は初回runでXcodeによるメタデータ生成まで成功したが、xtool生成wrapperへのコピーが欠けてIPA検査に失敗した。公式生成物を内容変更せず梱包する修正を再検証する段階で、SideStore導入と実機動作は未検証。後続工程の詳細は、その前段の実測結果を根拠に具体化する。全工程のコードまで確定した実行手順書とは扱わない。

**引継ぎ:** 計画作成後にこのWindows環境での続行指示を得たため、ローカル経路の検証を進めている。0.1の完成・リリースまでは非公開で保存する。文書のGit管理・非公開保存や基礎環境の準備は、アプリの実装・検証・OSS公開・0.1のリリースの完了ではない。

## Global Constraints

- 対象は「ミニアプリを束ねるスーパーアプリ」の基盤0.1。個別アプリの移植は対象外。
- 無料のAppleアカウントとSideStoreを最低条件にする。Mac購入は前提にしない。
- Windows上のWSLで先に検証する。不成立の場合だけGitHub Actionsが提供するクラウド上のmacOS環境でビルドする。
- 許容する作業は既存OSSと薄い接続処理まで。ツール内部の改造や生成メタデータの手修正が必要になったら中断する。
- 最初の実機条件はユーザー申告のiPhone 16e／iOS 26.6／SideStore 0.6.3。実行前に表示バージョンを確認する。
- F1〜F7・O1〜O4の全達成が0.1の完成条件。名称変更・工程分割・後続版の計画を理由に削除・縮小・延期しない。
- ショートカット実行中にアプリ画面が開いてもよい。Widgetは表示専用とし、即時更新保証は含めない。
- 実装技術の判断は実装側が行う。機能、データ、費用、運用の手間に影響する変更は説明する。
- ブランチは事前明示なしに作成しない。既存のGitリポジトリを再初期化しない。GitHub公開は承認後。
- 各タスク（チェックボックスまたは同等の独立作業単位）を完了し、必要な検証を通した時点で、そのタスクに属する変更だけをローカルGitコミットとしてチェックポイント化する。ユーザーから別途指示があるまでpushしない。
- Appleの認証情報、個人の署名鍵、実データ、Apple SDK本体をGit・公開物へ含めない。
- 0.1を1.0へ育てる方向性とYAGNIを判断指針にする。適用できるスキルや根拠のある設計原則に照らして調整できるが、機能要求・完成条件・明示的制約は維持する。

## 作成するファイルと境界

以下の文書・設定の役割を先に決める。Swiftソースの具体的なターゲット配置は、工程1でビルド経路を確認してから決める。

| パス | 担当 |
| --- | --- |
| `README.md` | 製品像、できること、対応環境、導入手順への入口 |
| `LICENSE` / `THIRD_PARTY_NOTICES.md` | MITと第三者の利用・配布条件 |
| `CONTRIBUTING.md` / `SECURITY.md` / `CHANGELOG.md` | 変更提案、脆弱性報告、リリースの変更履歴 |
| `.gitignore` | ビルド成果物・SDK・認証情報等の混入防止 |
| `docs/build.md` / `docs/sidestore.md` | 実証したビルドと再署名・導入の手順 |
| `docs/mini-apps.md` / `docs/updating.md` | ミニアプリの追加、公開基盤の更新取り込みと競合解消後の確認 |
| `docs/verification/0.1.md` | F1〜F7・O1〜O4の状態、実行環境、実測結果、証拠への参照 |
| `docs/decisions/build-route.md` | ツール・SDKの固定版、ビルド経路、ローカル不成立時の理由 |
| ビルド経路が要求するマニフェスト・設定 | ホスト・Widget・共有処理のビルド対象。確定した経路に必要なものだけ作成する。 |
| ホスト・ミニアプリ・共有処理・テストのソース | 技術確認文書の責務分担を実装する。各工程に入る前に具体的なパスと公開する型・テストを記載する。 |

最後の2行は未検証のファイル構成を確定したように見せないための境界であり、実装担当が自由に完成条件を変える余地ではない。将来のIPA変換器や汎用サービスのファイルは用意しない。

## 工程1：ビルド経路と検証条件を確定する

**成果物:** `docs/decisions/build-route.md`、`docs/verification/0.1.md`、実際に導入確認する最小アプリ。

**入口:** 実装・環境構築の開始指示を得ていること。必要な認証や取得条件を説明し、費用・利用枠の変更は別途確認する。

- [x] Windowsで次の読取り専用コマンドを実行し、利用可能なツールとWSLディストリビューションを記録する。利用者名・端末識別子等の不要な個人情報は記録しない。

```powershell
Get-Command git, wsl, swift, xtool, gh -ErrorAction SilentlyContinue |
    Select-Object Name, Source
wsl --list --verbose
```

- [x] WSL内で次を実行する。見つからないツールは未導入として記録し、その終了結果を成功扱いしない。この段階ではインストールしない。

```sh
cat /etc/os-release
command -v swift
command -v xtool
command -v cargo
```

- [x] 見つかったSwiftとxtoolについて、次のバージョン・利用可能オプションを確認する。未導入なら提供元の手順から導入に必要な作業・容量・取得条件を整理する。

```sh
swift --version
swift sdk list
xtool --help
xtool dev build --help
```

- [x] 技術確認文書で参照したxtoolと代替メタデータ生成ツールの版・配布条件を再確認し、採用または保留する版、取得元、理由を`docs/decisions/build-route.md`へ記す。単に`latest`だけを記録して終わらせない。
- [x] Apple SDKは正規の取得手順を使う。ユーザーによるAppleへのログイン・利用条件の確認が必要な箇所を切り分ける。認証情報を文書やコマンド履歴へ書かせない。Xcode 26.6 Universalのブラウザ取得と実ファイル検証を行い、Apple Developer Services認証を使わずDarwin Swift SDKを生成・導入した。
- [x] 合意した範囲で必要な環境を準備した後、提供元の最小アプリ例でビルド・IPA出力を実行する。Swift 6.3.3、xtool 1.17.0、Darwin Swift SDKを使い、Apple認証なしでarm64 `.app`と未署名IPAを生成した。実際のコマンド、終了結果、リポジトリ外の成果物の場所は`docs/decisions/build-route.md`に記録した。
- [x] 最小アプリで、数値を受け取って結果を返すApp Intentと、同じ値を表示するWidgetを実証するための具体的なファイル・型・テスト手順を本計画へ追加する。下記の「App Intent／Widget最小実証の実装境界」に固定し、この詳細が揃ってからコードに着手する。
- [x] ローカル経路の不成立を受け、GitHub Actionsの`macos-26`、Xcode 26.6、xtool 1.17.0、Xcode workspace生成、アドホック署名、App Intentsメタデータ検査、7日間のIPA artifactまでを`.github/workflows/build-ios.yml`へ具体化する。自動起動とAppleのsecretは入れず、利用枠・料金・未実行状態を`docs/decisions/build-route.md`へ記録する。
- [ ] GitHubへpush済みのworkflowを手動実行し、`Metadata.appintents/extract.actionsdata`を含むIPAがuploadされたこと、jobのXcode・xtool版、SHA-256、実行時間、消費した利用量を記録する。初回run `33392043166`ではXcode生成まで成功したが`.app`へのコピーが欠けて失敗したため、公式生成ディレクトリを内容変更せず梱包する修正を再実行する。workflowの存在や途中工程だけで成功扱いにしない。
- [ ] SideStore経由で最小アプリを導入し、ショートカットへの登録・入出力とWidgetの共有領域読取りを確認する。再署名後の識別子、本体と拡張、消費した枠を記録する。
- [x] ローカル経路の失敗を以下の区分で整理し、ツール内部や生成物を改造せずmacOS経路へ切り替える。今後の失敗も原因に対応しないビルド環境の変更を繰り返さない。

| 結果 | 次の行動 |
| --- | --- |
| ローカルのビルド・メタデータ生成が許容範囲で成立 | 使用した経路を固定し、工程2へ進む。 |
| ローカルのツール側で不成立 | 不成立理由を説明し、合意済みのGitHub Actionsのクラウド上のmacOS環境で同じ必須操作を確認する。利用枠と必要設定を先に示す。 |
| IPAは作れるが署名・共有領域・実機連携が不成立 | SideStore再署名後の設定・識別子・権限を調べる。クラウドへ移すだけで解決すると決めつけない。 |
| ツール内部の改造や生成物の手修正が必要 | その経路を中断し、未達条件・原因・必要な変更を示す。0.1を縮小して完了扱いにしない。 |

### App Intent／Widget最小実証の実装境界

これは捨てるための別プローブではなく、工程2のカウンターへ継続利用する最小の製品ソースとして作る。App Intentは外部から価値のある1操作だけ、Widgetは表示だけとし、AppEntity、設定画面、即時更新機構は追加しない。最初の実機がiOS 26.6であるため、当面のdeployment targetはiOS 26.0とし、対象OSの拡張は別の実測後に判断する。

| パス | 作成する内容・公開する型 |
| --- | --- |
| `Package.swift` | SwiftPM 6.0。`AppbaseIOS`、`CounterFeature`、`AppbaseIOSWidget`の3 targets、アプリとWidgetの2 library products、`CounterFeatureTests`を宣言する。アプリとWidgetだけが`CounterFeature`へ依存する。 |
| `xtool.yml` | 暫定bundle ID、アプリproduct、Widget extension product、本体・拡張それぞれのInfo.plistとentitlementsを宣言する。実機更新に使う恒久bundle IDは、最初の署名前に別途固定する。 |
| `AppbaseIOS.entitlements` / `AppbaseIOSWidget.entitlements` | 同じ論理App Groupを宣言する。資格情報やTeam IDは書かない。 |
| `AppbaseIOS-Info.plist` / `AppbaseIOSWidget-Info.plist` | 論理App Group名を`AppbaseAppGroup`へ持たせる。Widget側は`com.apple.widgetkit-extension`を宣言する。 |
| `Sources/CounterFeature/CounterFeature.swift` | `CounterStore` actorを公開し、`currentValue()`と`add(_:)`だけを提供する。App Groupの`UserDefaults`を使い、画面とApp Intentを同じ更新処理へ通す。 |
| `Sources/CounterFeature/SharedGroupResolver.swift` | `SharedGroupResolver`を公開する。SideStoreがInfo.plistへ入れる`ALTAppGroups`の`[String]`から論理App Groupの末尾に一致する候補を1件だけ選ぶ。見つからない・複数候補の場合は黙って通常のUserDefaultsへ切り替えず、判別可能な失敗にする。通常署名では`AppbaseAppGroup`の値を使う。 |
| `Sources/AppbaseIOS/AppbaseIOSApp.swift` / `CounterScreen.swift` | 最小のアプリ入口とカウンター画面。画面は`CounterStore`の現在値を読み、同じ`add(_:)`で更新する。 |
| `Sources/AppbaseIOS/AddCounterValueIntent.swift` | `AddCounterValueIntent: AppIntent`。`amount: Int`を受け、`CounterStore.add(_:)`の更新後の`Int`を`ReturnsValue<Int>`として返す。iOS 26の`supportedModes = [.background]`を使い、画面を開くことに依存しない。 |
| `Sources/AppbaseIOS/AppbaseShortcuts.swift` | `AppbaseShortcuts: AppShortcutsProvider`。上記Intentを「カウンターに追加」として1件だけ登録する。Intent宣言をホストtargetへ集め、複数moduleのメタデータ集約を要求しない。 |
| `Sources/AppbaseIOSWidget/CounterWidget.swift` | `CounterWidget`と読取り専用`TimelineProvider`。同じ`CounterStore.currentValue()`を読み、Widgetからは書き込まない。即時更新は保証しない。 |
| `Tests/CounterFeatureTests/CounterFeatureTests.swift` | 値の加算と保存先解決の分岐だけを検査する。App IntentsやWidgetKitをLinux単体テストで動作済み扱いにしない。 |

実装後の確認順は次のとおり。

1. WSLで`swift test`を実行し、iOS非依存の加算と保存先解決を確認する。TDDはこの小さな更新規則に使い、iOSフレームワークの実機確認を単体テストへ偽装しない。
2. `xtool dev build --ipa`を実行し、終了コードとIPAを記録する。`unzip -t`に加え、`Payload/AppbaseIOS.app/PlugIns/AppbaseIOSWidget.appex`、本体とWidgetのInfo.plist、両バンドルのentitlementsを確認する。
3. ビルド成功とは別に、`Payload/AppbaseIOS.app/Metadata.appintents/extract.actionsdata`の有無を確認する。xtool 1.17.0の固定タグにはApp Intentsメタデータ生成処理がなく、Issue #145も未解決なので、ファイルがなければF2のローカル経路は不成立と判定する。
4. メタデータがない場合、生成物の手修正やxtool内部の改造は行わない。同じ標準SwiftソースをGitHub Actionsが提供するmacOS環境でビルドする具体的なjob、Xcode版、成果物確認を計画へ追記してからクラウド経路を試す。`macos-26`、Xcode 26.6、xtool 1.17.0を固定し、手動実行だけの`.github/workflows/build-ios.yml`へ具体化した。
5. メタデータを含むIPAが得られた後にSideStoreで導入する。ショートカット一覧に「カウンターに追加」が現れること、`2`を渡すと更新後の値`2`が返ること、アプリ画面も`2`を表示すること、WidgetがOSの更新後に同じ`2`を表示することを実機で確認する。再署名後の本体・拡張bundle ID、解決したApp Group、消費したApp ID枠も記録する。

WSLでのコンパイル、IPA内のメタデータ、SideStore署名、Shortcuts実行、Widget共有値を別々の証拠として扱う。どれか1つの成功で残りを完了扱いにしない。

**2026-08-30の実行結果:** `swift test`は5件合格し、`xtool dev build --ipa`も終了コード0。Widget extensionとApp Intent型を含むarm64 IPAは生成できたが、`Metadata.appintents/extract.actionsdata`は存在しなかった。手順3の判定に従い、ローカルツール側の不成立として、手順4のmacOSクラウド経路の具体化へ進む。

**完了判定:** 採用する経路において、最小アプリのビルドとSideStore導入、App Intentの登録・入出力、Widgetの共有値の表示を実際に確認し、再現可能な手順を記録できたこと。これは0.1全体の完成ではない。

## 工程2：継続して育てる本体とカウンターを作る

**対応:** F1、F2、F3、F7の途中検証。

**成果物:** ホストの一覧・遷移、カウンターの画面・保存・共通更新処理、App Intent、表示用Widget。工程1の実証で使えるコードは整えて継続利用し、無条件に作り直さない。

- [ ] 工程1の結果に基づき、各ファイルのパス、担当、使う型・関数、ビルド・テストコマンドをこの工程に追記する。iOSでしか検証できない部分とWSLで試せる処理を分ける。
- [ ] 更新処理と保存のテストを先に作り、失敗を確認してから必要な処理を実装する。画面とショートカットからの更新を意図的に同時進行させ、全更新を反映した期待値が保存後と再読込み後にも一致し、更新が失われないケースを含める。逐次実行だけではこの確認を完了扱いにしない。
- [ ] ホストの一覧からカウンターを開き、値を変更する。本体を再起動し、値が残ることを実機で確認する。
- [ ] ショートカットで数値を渡し、更新後の値が戻ること、画面にも反映されることを確認する。アプリ画面が開く実行を許容する。
- [ ] 本体とWidgetが再署名後も同じ共有領域を選び、保存値を表示できることを確認する。共有領域が不明なときは別の保存先へ黙って切り替えない。
- [ ] 実際に使う設定だけでビルドできるよう整え、`docs/build.md`へ手順を記す。

**完了判定:** F1〜F3の操作が実機で成立し、工程1で採用した経路からこの段階のIPAを再生成できる。本体にカウンター固有の保存・更新処理を埋め込まない。F7の最終判定は、F1〜F6を含む製品全体を工程4で再生成するまで行わない。

## 工程3：通知と第2ミニアプリで追加方法を確かめる

**対応:** F4、F5、O2の追加手順。

**成果物:** 通知の受け取り口、通知からの遷移、第2の独立したサンプルミニアプリ、`docs/mini-apps.md`。

- [ ] 実装するファイル・型と検証コードをこの工程に追記する。第2ミニアプリは保存先・起動先の独立を確認できる簡単な用途にし、個別アプリの移植を持ち込まない。
- [ ] ミニアプリID・保存先・通知ID・起動先の衝突を検出するテストを作り、失敗を確認してから登録を整える。
- [ ] 利用者の操作で通知を予約し、通知から該当ミニアプリへ戻れることを、本体の起動中と終了状態から確認する。
- [ ] 通知を拒否しても通常操作を続けられること、起動だけでは通知許可を要求しないことを確認する。
- [ ] 未登録または更新前の古いミニアプリID・起動先を持つ通知を受け取っても、クラッシュや別ミニアプリへの誤遷移を起こさず、安全な既定画面へ戻れることを確認する。
- [ ] 第2ミニアプリを一覧へ追加し、両方の保存値と起動先が衝突しないことを確認する。通常の登録・ビルド宣言以外に、ホストの共通処理を書き換えていないか差分を見る。
- [ ] 実際に変更した箇所から追加手順を書く。WidgetやApp Intentの追加設定も、通常の画面追加との違いを説明する。

**完了判定:** F4・F5が成立し、文書に従う追加手順と実際の変更箇所が一致する。

## 工程4：更新・署名更新後の継続動作を確かめる

**対応:** F6、F7の最終判定、O2の更新手順、O3の検証記録。

**成果物:** 更新前後のIPAと対応するソース、`docs/sidestore.md`、`docs/updating.md`、実機検証記録。

- [ ] 同じAppleアカウント・アプリ識別子で、保存済みデータと各連携を持つ更新前の状態を作る。
- [ ] 追跡可能な別ビルドをSideStoreで更新インストールし、F1〜F5を再確認する。
- [ ] SideStoreで署名更新し、保存値、Widget、ショートカット、通知からの起動を再確認する。
- [ ] アカウント変更・アプリ識別子変更・アンインストールと再導入まで同じ保証を広げない。対応済み条件と別途移行が必要な条件を文書化する。
- [ ] 公開基盤と個人用コードの編集箇所、更新の取り込み、競合が発生した場合の解消と確認手順を記す。ユーザーの実リポジトリやブランチを無断で作成・変更して説明を実証しない。
- [ ] 工程1で採用したビルド経路をクリーンな状態から再実行し、F1〜F6をすべて含む製品IPAを生成してSideStoreで導入・確認する。工程2以降で追加した構成によりローカル経路が不成立になった場合は、理由を記録してビルド経路の判定を再開し、合意済みの条件に従ってGitHub Actionsのクラウド経路を検証する。確定した最終手順を`docs/build.md`と検証記録へ反映する。

**完了判定:** F6が成立し、F1〜F6を含む製品IPAをMac購入不要の確定した手順から再生成できる。操作した環境・版・手順・結果を追跡でき、F7もここで最終判定できる。

## 工程5：GitとGitHubで保守・公開できる状態にする

**対応:** O1、O2、O3。

**成果物:** Git管理されたプロジェクト、ライセンス、運用文書、自動チェック、承認された公開先。

- [ ] 既存のGitリポジトリ、remote、既定ブランチ`main`、GitHubの非公開設定と公開切替手順を確認する。再初期化や新しいブランチ作成を前提にせず、ブランチが必要な場合は事前に説明する。この工程の達成には公開・運用の成果物も必要。
- [ ] `LICENSE`、`THIRD_PARTY_NOTICES.md`、`.gitignore`を整え、使用・配布する第三者コードとSDK・鍵の混入を確認する。
- [ ] `README.md`、`CONTRIBUTING.md`、`SECURITY.md`、`CHANGELOG.md`と各手順文書を、実際の構成・実行方法・確認済み環境に一致させる。
- [ ] 確定したビルド経路で実行できる自動チェックを設定する。外部からの変更提案に認証情報を渡さない。実機検証を自動チェックの合格で代用しない。
- [ ] 各タスクの完了と検証後、そのタスクに属する変更だけをローカルコミットとしてチェックポイント化する。明示したブランチ運用とプルリクエストの手順を適用し、pushはユーザーの別指示まで行わない。説明だけで実施済みに数えない。
- [ ] GitHubの非公開リポジトリ上でソース、ライセンス、文書、チェック結果を確認する。公開切替は工程6で0.1のリリースと合わせて行う。

**完了判定:** O1〜O3の公開前の成果物が存在し、書かれた手順が実際の操作に対応している。公開リポジトリの確認を含むO1の最終達成は工程6に残す。

## 工程6：0.1のリリースを確認する

**対応:** O4、およびF1〜F7・O1〜O4の最終照合。

- [ ] `docs/verification/0.1.md`の全11項目について、公開前に確認可能な実行結果・成果物を揃える。実装・検証の未達があれば公開に進まない。公開待ちのO1・O4はその状態のまま残す。
- [ ] リリースするソース、正式番号`0.1.0`、Gitタグ、変更履歴、IPAを対応付ける。最終ビルドと同じ版について実機結果を確認する。
- [ ] 公開前に、認証情報・個人の署名鍵・実データ・Apple SDK本体を成果物に含めていないことを確認する。
- [ ] 0.1の完成時に公開する方針に従い、公開準備が揃った状態でリポジトリを公開へ切り替え、0.1のリリースを作成する。公開されたIPAとソース・文書の対応を確認し、O1・O4の公開を伴う条件も完了にする。

**完了判定:** 全11項目を満たす公開リリースが存在する。コード完成、ビルド成功、検証用IPA、タグの作成だけでは0.1の完成にしない。

## 完成条件との対応

| 条件 | 担当工程 | 確認する結果 |
| --- | --- | --- |
| F1 起動・保存 | 2・4 | 一覧から開け、再起動と更新後も値が残る。 |
| F2 ショートカット | 1・2・4 | 登録、数値入力、更新、戻り値が成立する。 |
| F3 Widget | 1・2・4 | 再署名後も共有値を表示する。 |
| F4 ローカル通知 | 3・4 | 予約、拒否の扱い、通知からの遷移が成立する。 |
| F5 ミニアプリ追加 | 3 | 保存先・起動先が衝突せず、ホスト共通処理の書換えを要求しない。 |
| F6 SideStore導入・更新 | 1・4 | 無料アカウントで導入・更新・署名更新後も各操作が成立する。 |
| F7 Mac購入不要のビルド | 1〜4 | 最小構成で経路を選定した後、F1〜F6を含む製品IPAをローカル優先と条件付きクラウド経路のもとで再現できる。 |
| O1 Git・公開・ライセンス | 5・6 | 0.1のリリース時に公開リポジトリとライセンス表示が存在する。 |
| O2 文書 | 2〜5 | 導入・追加・更新・貢献・問題報告を実際の手順で説明できる。 |
| O3 チェック・検証記録 | 1〜5 | 自動チェックと実機結果を区別して追跡できる。 |
| O4 リリース成果物 | 6 | ソース、タグ、変更履歴、IPAが対応する。 |

## 実装手順を具体化する際の規則

各工程のコードへ着手する前に、前工程の実測結果から具体的なファイル構成・型・テストコード・実行コマンドを記載する。実装済みの自然なテスト配置があればそれを使う。新しい依存関係・抽象化・テストファイルは必要性があるものだけ加える。

この具体化を口実に、工程を無期限に増やしたり、必須条件を後続版へ移したりしない。実行可能な詳細が不足する状態で作業者へ丸投げせず、未検証の手順を成功するものとして提示しない。
