# ビルド経路の判断記録

更新日: 2026-08-30

**状態:** 調査中。採用するビルド経路は未確定。WSL 2、Ubuntu 24.04、Swift 6.3.3、xtool 1.17.0、Xcode 26.6由来のDarwin Swift SDKを使い、製品へ継続利用する最小構成からApp Intent型とWidget extensionを含むIPAを生成できた。ただしApp Intentsメタデータが生成されないためF2のローカル経路は不成立。GitHub ActionsのmacOS経路はローカルにworkflowを用意したが、まだpush・実行していない。SideStore導入と実機動作も未検証。

## Windows環境の初期確認

2026-08-29に読取り専用で確認した。

| 対象 | 確認結果 |
| --- | --- |
| Windows | レジストリ表示は`Windows 10 Home`、`25H2`、ビルド`26200.9168`。この表示を記録し、製品名を別の版として推定しない。 |
| Git | `2.50.0.windows.1`を利用可能。 |
| `wsl.exe` | Windowsのシステムコマンドとして存在する。 |
| WSL本体・Linuxディストリビューション | `wsl --list --verbose`と`wsl --status`はいずれも終了コード1で、WSLのインストール案内を表示した。利用可能なディストリビューションは確認できず、WSL環境は未導入として扱う。 |
| Swift | Windows側でコマンドが見つからない。 |
| xtool | Windows側でコマンドが見つからない。 |
| GitHub CLI | Windows側でコマンドが見つからない。 |

WSL内のSwift・xtool・cargo確認は、実行可能なLinuxディストリビューションがないため未実施。未実施の確認を成功扱いにしない。

## WSL導入結果

2026-08-29にWSL 2とUbuntu 24.04を導入した。

| 項目 | 結果 |
| --- | --- |
| WSL | `2.7.12.0` |
| Linuxカーネル | `6.18.33.2-2` |
| ディストリビューション | `Ubuntu 24.04.4 LTS`、WSL 2 |
| 既定ユーザー | `dev`（UID 1000、ホーム`/home/dev`、パスワードはロック済み） |
| Swift | `6.3.3`を導入済み。導入前の`which swift`は終了コード1 |
| xtool | `1.17.0`を導入済み。導入前の`which xtool`は終了コード1 |
| cargo | 未導入。`which cargo`は終了コード1 |

個人名を環境へ含めないため、開発用ユーザー名は`dev`とした。通常作業は`dev`で行い、パッケージ導入等の管理操作だけをWindows側から明示的にroot指定する。パスワードや無制限のpasswordless sudoは設定していない。

## Swift導入結果

2026-08-29にUbuntu 24.04向けの公式依存パッケージとSwiftly 1.1.2を導入し、Swift 6.3.3を固定した。

| 項目 | 結果 |
| --- | --- |
| Swiftly | `1.1.2`。公式アーカイブと署名を取得し、Swift公式鍵のfingerprint `E813 C892 820A 6FA1 3755 B268 F167 DF1A CF9C E069`によるGood signatureを確認 |
| Swift | `6.3.3 (swift-6.3.3-RELEASE)`、target `x86_64-unknown-linux-gnu`。Swiftly側の署名検証を有効にして導入 |
| バージョン固定 | リポジトリ直下の`.swift-version`に`6.3.3`を記録。Swiftlyのglobal defaultも6.3.3 |
| 最小確認 | 一時的な実行可能Swiftパッケージを生成し、`swift build`成功後に`swift run`で`Hello, world!`を確認 |

Swiftlyの管理領域は`/home/dev/.local/share/swiftly`で約3.4 GiB。検証用パッケージは製品実装ではなく、Linuxホスト用SwiftコンパイラとSwift Package Managerが動作することだけを確かめるためにユーザーキャッシュ配下で作成した。この成功をiOSアプリやIPAのビルド成功とは扱わない。

## xtool導入結果

2026-08-29にGitHubの公式release `1.17.0`からx86_64 AppImageを`/home/dev/.local/bin/xtool`へ導入した。

| 項目 | 結果 |
| --- | --- |
| release | `1.17.0`、コミット`9e8bfd432c99c7ef9ade6c4b6723f1321ed0e7ed` |
| AppImage | `xtool-x86_64.AppImage`、53,594,616 bytes |
| SHA-256 | GitHub release APIのdigest `7566d62b829a4deadb01b5389c94f45763d851f204c5d22fa36e9f9d1c88d57b`と実ファイルが一致 |
| 起動確認 | `xtool --version`は`xtool 1.17.0`。`xtool --help`と`xtool dev build --help`は終了コード0 |
| Darwin Swift SDK | 導入前の`swift sdk list`は`No Swift SDKs are currently installed.`。Xcode 26.6取得後に導入し、現在は`darwin`を表示 |

`xtool setup`はApple Accountの認証情報とXcode 26のXIPを要求するため実行していない。ヘルプ起動の成功だけを、Apple認証、Darwin SDK生成、iOSビルド、署名、実機導入の成功として扱わない。

## Apple SDK取得の境界

2026-08-30時点の安定版で、xtool 1.17.0と導入済みSwiftに合うXcode 26.6 Universalを採用し、Darwin Swift SDKを生成した。

| 項目 | 判断 |
| --- | --- |
| Xcode | `26.6`、build `17F113`、Swift `6.3.3`、iOS SDK `26.5` |
| 取得物 | `Xcode_26.6_Universal.xip`。x86_64を含むUniversal版。実ファイルは2,965,708,631 bytesで、Appleの画面表示は2.76 GB |
| 公式取得先 | [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Xcode%2026.6)。ブラウザでApple Accountへログインし、表示された利用条件をユーザーが確認・同意して取得する |
| 取得前の状態 | 公式URLへの未認証HEAD要求は`/unauthorized/`へredirectされた。Apple Accountへログイン済みのブラウザから取得し、認証情報をコマンド履歴へ入れていない |
| XIP検証 | ファイル先頭がXIPの`xar!`であることと、SHA-1 `31f49573964bb9b13f1c5f4bad83a23e3be2a44e`が公開releaseカタログの値と一致することを確認 |
| SDK生成 | Apple Developer Servicesへログインせず`xtool sdk install <path>`を実行して成功。`iPhoneOS26.5.sdk`、`iPhoneSimulator26.5.sdk`、`MacOSX26.5.sdk`を含む`darwin.artifactbundle`を生成 |
| 導入確認 | `swift sdk list`は`darwin`、`xtool sdk status`は`/home/dev/.swiftpm/swift-sdks/darwin.artifactbundle`への導入済み状態を表示 |
| Apple認証 | `xtool auth status`は`Logged out`。SDK生成時はこの状態を維持し、署名・実機導入が必要になるまで`xtool auth login`を実行しない |

Appleの公式資料ではXcode 26.6が安定版であること、build、Swift・SDKの版を確認した。ログイン前にAppleからchecksumは取得できなかったため、取得後の実ファイルを公開releaseカタログのSHA-1と照合した。XIPの個人別Downloadsパスは文書へ記録せず、XIPと生成したDarwin SDKをGit管理外に置いている。

SDKの使用量は約3.2 GiB。展開用一時ディレクトリは処理終了後に約12 KiBまで縮小し、生成途中のXcode.appは残っていない。取得したXIPは後続の再現性確認に備えて削除せず保持している。

## 最小アプリとIPAの生成結果

2026-08-30にxtool 1.17.0自身のジェネレータを使い、リポジトリ外のWSLキャッシュ領域へ`AppbaseXtoolProbe`を生成した。`--skip-setup`で認証とSDK再設定を明示的に省き、ビルド後も`xtool auth status`が`Logged out`であることを確認した。

```sh
export PATH=/home/dev/.local/share/swiftly/bin:/home/dev/.local/bin:$PATH
cd /home/dev/.cache
xtool new AppbaseXtoolProbe --skip-setup
cd AppbaseXtoolProbe
xtool dev build
xtool dev build --ipa
```

生成された例はSwift tools 6.0、iOS 17以上、macOS 14以上を宣言し、SwiftUIの`WindowGroup`から`ContentView`を表示するだけの構成だった。製品用のbundle IDや設計を確定する材料にはせず、ビルド経路のプローブとしてのみ扱う。

| 項目 | 結果 |
| --- | --- |
| `.app` | 初回ビルドは52.58秒で終了コード0。`/home/dev/.cache/AppbaseXtoolProbe/xtool/AppbaseXtoolProbe.app`へ出力 |
| IPA | キャッシュ利用後のビルドは0.47秒で終了コード0。`/home/dev/.cache/AppbaseXtoolProbe/xtool/AppbaseXtoolProbe.ipa`へ出力 |
| 保存した検証成果物 | `/home/dev/.cache/AppbaseXtoolProbe-artifacts-20260830/`に`.app`とIPAを保存。リポジトリ外でありGit管理対象外 |
| IPA検証 | 106,011 bytes、SHA-256 `ed358948f12c5aaa1168298fcb9447c2a2070dd2a1df870a6a0c19dd6fd0eaf9`。`unzip -t`は全4項目を正常と判定 |
| 実行ファイル | 103,680 bytesの64-bit arm64 Mach-O。iPhone実機向けの既定tripleで生成 |
| 署名 | `.app`に`_CodeSignature`は存在しない。ビルドとIPA梱包の成功だけを確認し、SideStoreによる再署名・導入成功とは扱わない |

`xtool dev build --ipa`は同じ`xtool`出力ディレクトリを作り直すため、直前の`.app`は残らない。上記の保存先では、`.app`ビルド後にコピーしてからIPAを生成して両方を保持した。

## App IntentとWidgetの着手判定

2026-08-30にxtool 1.17.0の固定タグをコミット`9e8bfd432c99c7ef9ade6c4b6723f1321ed0e7ed`で取得し、提供元の文書とパッケージ処理を再確認した。

- Widgetは、SwiftPMの別library product、`xtool.yml`の`extensions`、Widget用Info.plistによって`.appex`として組み込める。本体と拡張には別々の`entitlementsPath`も指定できる。
- 固定タグのソースを`AppIntents`、`appintentsmetadataprocessor`、`Metadata.appintents`で検索した結果は該当なしだった。[Issue #145](https://github.com/xtool-org/xtool/issues/145)はOpenのまま、Linux向けメタデータ生成の[PR #217](https://github.com/xtool-org/xtool/pull/217)は未マージで閉じている。
- したがって、標準のApp IntentsコードがクロスコンパイルできてもF2の成立証拠にはしない。IPA内の`Metadata.appintents/extract.actionsdata`と、実機のショートカット一覧への登録、数値入力、戻り値を別々に確認する。
- まずAppleの公開APIだけで継続利用する製品ソースを作る。メタデータが生成されなければローカルツール側の不成立として記録し、生成物の手修正やxtool内部の改造は行わず、合意済みのGitHub Actions上のmacOS経路へ進む。
- `re-appintentsmetadataprocessor`は、ライセンス配布物、iOS向け出力、xtoolへの薄い接続だけで使えることをまだ実証できていないため、現時点では導入しない。

### 製品最小構成の実測

計画に具体化したアプリ、`CounterFeature`、Widgetの3 targetsを実装し、2026-08-30に次を確認した。

| 確認 | 結果 |
| --- | --- |
| Linux単体テスト | `swift test`で加算・保存とSideStore App Group解決の5件が合格。x86_64 Linux上の結果であり、iOSフレームワークや実機の合格ではない |
| iOSビルド | `xtool dev build --ipa`は終了コード0。App Intent、本体、Widgetをコンパイル・リンクし、entitlements付き擬似署名後にIPAを生成 |
| IPA | `xtool/AppbaseIOS.ipa`、488,929 bytes、SHA-256 `8760a8a269dd3f3ab099b7c94f83d7bcb220579efb519bb471f529b79768a007`。ビルド成果物なのでGit管理外 |
| IPA整合性 | `unzip -t`で12項目すべて正常。本体とWidgetの実行ファイルはいずれも64-bit arm64 Mach-O |
| Widget | `Payload/AppbaseIOS.app/PlugIns/AppbaseIOSWidget.appex`、Widget extension point、本体・Widget双方の論理App Group文字列を確認 |
| App Intentコード | 本体バイナリに`AddCounterValueIntent`と`AppbaseShortcuts`の型・適合情報が存在 |
| App Intentsメタデータ | `Payload/AppbaseIOS.app/Metadata.appintents/extract.actionsdata`は存在しない。Shortcutsへの登録条件を満たしたとは扱わない |
| 版と識別子 | 本体・Widgetとも`CFBundleShortVersionString`は`0.1.0`、buildは`1`。`com.example`のbundle IDは未署名検証用の暫定値 |

この結果は、Widgetを含むIPA生成はローカルで成立した一方、F2に必要なApp Intentsメタデータ生成はxtool 1.17.0の機能不足で不成立、という区分になる。同じ標準SwiftソースをGitHub Actionsが提供するmacOS環境でビルドする経路を次に具体化する。SideStore導入は、メタデータを含むIPAが得られてから行う。

## GitHub ActionsのmacOS経路

2026-08-30に`.github/workflows/build-ios.yml`をローカルへ追加した。意図しない利用枠消費を避けるため`workflow_dispatch`だけを入口とし、pushやpull requestでは自動実行しない。この文書更新時点ではworkflow自体をGitHubへpushしておらず、以下は実行済みの結果ではなく、次に検証する固定手順である。

| 項目 | 固定した内容 |
| --- | --- |
| runner | GitHub標準runnerの`macos-26`。現在の公式一覧ではApple Silicon、3 CPU、7 GB RAM、14 GB SSD |
| Xcode | `/Applications/Xcode_26.6.app`を`xcode-select`で明示し、`xcodebuild -version`の先頭行が`Xcode 26.6`であることを検査。runner imageの現在の一覧ではbuild `17F113` |
| xtool | 公式release `1.17.0`の`xtool.app.zip`。GitHub release APIのSHA-256 `7796364f6b568f3a728ec4afef1d6ccd4b12bdfbca1b33a92cbead65545ed2fe`との一致を必須にする |
| プロジェクト生成 | macOSだけで有効な`xtool dev generate-xcode-project`を使う。xtool 1.17.0の固定ソースを確認し、本体とWidgetをXcode targets、リポジトリ直下をlocal packageとして生成することを確認した |
| ビルド | Xcode workspaceの`AppbaseIOS` schemeを、iOS実機向けReleaseとして`xcodebuild`する。Apple署名情報をrunnerへ渡さず、最初は`CODE_SIGNING_ALLOWED=NO`で生成する |
| 署名・梱包 | SideStoreへ渡す資格情報を残すため、Widgetを先、本体を後の順に、リポジトリ内のentitlementsを使ってmacOS標準`codesign`でアドホック署名する。Apple証明書、provisioning profile、Apple Accountのsecretは使わない |
| 合格条件 | arm64の本体とWidget、bundle ID、0.1.0／build 1、両バンドルの論理App Group、`Metadata.appintents/extract.actionsdata`の非空ファイル、IPAのZIP整合性をjob内で検査する。いずれかが欠ければIPAを成果物としてuploadしない |
| 成果物 | `AppbaseIOS-ad-hoc`というActions artifactへIPAだけを保存し、保持期間は7日。実機合格前の検証物でありrelease成果物にはしない |

非公開リポジトリの標準runner利用は、所有者のプランに含まれるActions利用枠から消費され、超過分の費用もリポジトリ所有者に帰属する。2026-08-30現在、GitHub Freeは月2,000分とartifact 500 MBを含み、標準macOS runnerの基準単価は超過時$0.062／分と案内されている。料金と残量は変更され得るため、最初の手動実行前に[Actionsの課金説明](https://docs.github.com/en/billing/concepts/product-billing/github-actions)と[Billing画面](https://github.com/settings/billing)で実際のアカウント状態を確認する。公開リポジトリにして無料化するために、0.1完成時まで非公開という公開方針を前倒ししない。

この経路が満たすのは、Macを購入せずXcodeの正規ビルド処理を使えるかという確認までである。App Intentsメタデータ入りIPAが生成できても、Shortcutsへの表示・入出力、SideStore再署名後のApp Group、Widget表示を実機で別に確認する。

## 現時点の判断

- Windows上のWSLで、Apple Developer ServicesへログインせずWidgetを含む未署名iOS IPAを生成する部分は成立した。
- F2のApp Intentsメタデータ生成はローカルツール側で不成立と判定した。ソースはAppleの公開APIだけで構成できており、生成物の手修正やxtool内部の改造は行わない。
- GitHub Actions上のmacOS経路を具体化し、利用枠と必要設定を記録した。次はユーザーのpush指示後に手動実行し、同じソースからメタデータ入りIPAを作れるか確認する。

## 公式要件と固定する候補

2026-08-29に提供元の資料とリリースタグを確認した。インストール時も以下の版を明示し、無条件に`latest`を使わない。

| 対象 | 固定する候補・判断 | 取得元・条件 |
| --- | --- | --- |
| WSL | WSL 2とUbuntu 24.04 LTSをローカル検証候補にする | [MicrosoftのWSL導入手順](https://learn.microsoft.com/windows/wsl/install)。`wsl --install`は管理者権限を使い、Ubuntuを導入して再起動を要求する場合がある。 |
| Swift | Ubuntu 24.04用Swift 6.3.3を候補にする | [SwiftのUbuntu向け導入手順](https://www.swift.org/install/linux/ubuntu/)と[tarball手順](https://www.swift.org/install/linux/tarball/)。公式リリースと署名を使い、開発snapshotは使わない。 |
| xtool | `1.17.0`、コミット`9e8bfd432c99c7ef9ade6c4b6723f1321ed0e7ed`を候補にする | [GitHub Release](https://github.com/xtool-org/xtool/releases/tag/1.17.0)。リリースタグの`LICENSE.md`はMIT。 |
| Apple SDK | Xcode 26.6 Universal（build `17F113`）から作るDarwin Swift SDKを候補にする | [Appleのダウンロード](https://developer.apple.com/download/all/?q=Xcode%2026.6)はブラウザでのApple Accountログインと利用条件の確認・同意が必要。Apple Developer Programの有料会員でなくてもXcodeのダウンロード自体は可能。XIPやSDKをリポジトリへ含めない。 |
| USB接続 | WSLからiPhoneを扱う段階でusbipdとusbmuxdを確認する | [xtoolのLinux／Windows導入手順](https://github.com/xtool-org/xtool/blob/1.17.0/Documentation/xtool.docc/Installation-Linux.md)。USBパススルー設定は最小アプリのビルドだけでは不要なので、実機接続前まで延期する。 |
| 代替App Intentsメタデータ生成 | `1.0.0`、コミット`074d2f640773a35e4f25e0b19aa2658163f9e8ec`を保留候補にする | [Codebergの公式リポジトリ](https://codeberg.org/viraptor/re-appintentsmetadataprocessor)。READMEと`Cargo.toml`はMITを表明するが、タグの配布物にライセンス本文ファイルがない。iOS・xtool・SideStoreとの接続も未実証なので、現時点では採用しない。 |

xtool 1.17.0の公式手順は、Swift 6.3、Xcode 26、Linux上の`usbmuxd`、WindowsではWSLとUSBパススルーを前提にする。無料Appleアカウントの場合に案内されるパスワード認証はAppleのprivate APIへ依存する。認証方式は成立性とリスクを分けて扱い、Apple Accountのメール、パスワード、2FA情報を文書・リポジトリ・コマンド履歴へ保存しない。

## 容量と環境変更

初期確認時のCドライブ空き容量は約65.1 GiB、WSL導入後は約61.5 GiB、Swiftとxtool導入後は約56.2 GiB。xtool本体は約52 MiB。取得したXcode 26.6 Universal XIPは2,965,708,631 bytesだった。

SDK導入後のDarwin Swift SDKは約3.2 GiB、WSL内の論理使用量は約8.7 GiB、Cドライブの空き容量は約39.8 GiBだった。xtoolの展開用一時データは削除されたが、拡張されたWSL仮想ディスクのホスト側割当ては自動では縮小していない。仮想ディスクの圧縮やXIP削除は環境を変えるため、必要性を説明して承認を得るまでは実施しない。

次はApp IntentとWidgetを含む最小実証の構成を具体化する。署名や実機が必要になるまではApple Developer Servicesへログインしない。

## 実行した確認

```powershell
Get-Command git, wsl, swift, xtool, gh -ErrorAction SilentlyContinue |
    Select-Object Name, CommandType, Source
wsl --list --verbose
wsl --status
git --version
gh --version
```

OS表示は`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`の`ProductName`、`DisplayVersion`、`CurrentBuild`、`UBR`から確認した。利用者名、端末名、端末識別子は記録していない。
