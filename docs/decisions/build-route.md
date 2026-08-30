# ビルド経路の判断記録

更新日: 2026-08-30

**状態:** 調査中。採用するビルド経路は未確定。WSL 2、Ubuntu 24.04、Swift 6.3.3、xtool 1.17.0、Xcode 26.6由来のDarwin Swift SDKの準備まで完了した。iOS向けアプリとIPAのビルドは未検証。

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

## 現時点の判断

- Windows上のWSLを優先する方針は維持するが、iOS向けローカル経路の成立・不成立はまだ判定しない。
- WSL、Swift、xtool、Darwin Swift SDKの基礎環境は成立した。次はApple Developer Servicesへログインしないまま提供元の最小アプリをビルドし、`.app`とIPAの生成可否を確かめる。
- GitHub Actionsのクラウド経路は、ローカル経路が許容範囲で成立しない場合だけ検証する。

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

次はxtool提供元の最小アプリ例を使い、Apple Developer Servicesへログインせず`.app`とIPAのビルドを試す。使用した版、コマンド、終了結果、成果物の場所を記録する。

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
