# ビルド経路の判断記録

更新日: 2026-08-29

**状態:** 調査中。採用するビルド経路は未確定。環境のインストール、Appleへのログイン、SDK取得、ビルドはまだ実施していない。

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

## 現時点の判断

- Windows上のWSLを優先する方針は維持するが、ローカル経路の成立・不成立はまだ判定しない。
- 調査結果と必要な環境変更を説明してから、WSL・Swift・xtool等のインストールへ進む。
- GitHub Actionsのクラウド経路は、ローカル経路が許容範囲で成立しない場合だけ検証する。

## 公式要件と固定する候補

2026-08-29に提供元の資料とリリースタグを確認した。インストール時も以下の版を明示し、無条件に`latest`を使わない。

| 対象 | 固定する候補・判断 | 取得元・条件 |
| --- | --- | --- |
| WSL | WSL 2とUbuntu 24.04 LTSをローカル検証候補にする | [MicrosoftのWSL導入手順](https://learn.microsoft.com/windows/wsl/install)。`wsl --install`は管理者権限を使い、Ubuntuを導入して再起動を要求する場合がある。 |
| Swift | Ubuntu 24.04用Swift 6.3.3を候補にする | [SwiftのUbuntu向け導入手順](https://www.swift.org/install/linux/ubuntu/)と[tarball手順](https://www.swift.org/install/linux/tarball/)。公式リリースと署名を使い、開発snapshotは使わない。 |
| xtool | `1.17.0`、コミット`9e8bfd432c99c7ef9ade6c4b6723f1321ed0e7ed`を候補にする | [GitHub Release](https://github.com/xtool-org/xtool/releases/tag/1.17.0)。リリースタグの`LICENSE.md`はMIT。 |
| Apple SDK | Xcode 26から作るDarwin Swift SDKを候補にする | [Appleのダウンロード](https://developer.apple.com/download/all/?q=Xcode)はブラウザでのApple Accountログインとライセンス同意が必要。Apple Developer Programの有料会員でなくてもXcodeのダウンロード自体は可能。XIPやSDKをリポジトリへ含めない。 |
| USB接続 | WSLからiPhoneを扱う段階でusbipdとusbmuxdを確認する | [xtoolのLinux／Windows導入手順](https://github.com/xtool-org/xtool/blob/1.17.0/Documentation/xtool.docc/Installation-Linux.md)。USBパススルー設定は最小アプリのビルドだけでは不要なので、実機接続前まで延期する。 |
| 代替App Intentsメタデータ生成 | `1.0.0`、コミット`074d2f640773a35e4f25e0b19aa2658163f9e8ec`を保留候補にする | [Codebergの公式リポジトリ](https://codeberg.org/viraptor/re-appintentsmetadataprocessor)。READMEと`Cargo.toml`はMITを表明するが、タグの配布物にライセンス本文ファイルがない。iOS・xtool・SideStoreとの接続も未実証なので、現時点では採用しない。 |

xtool 1.17.0の公式手順は、Swift 6.3、Xcode 26、Linux上の`usbmuxd`、WindowsではWSLとUSBパススルーを前提にする。無料Appleアカウントの場合に案内されるパスワード認証はAppleのprivate APIへ依存する。認証方式は成立性とリスクを分けて扱い、Apple Accountのメール、パスワード、2FA情報を文書・リポジトリ・コマンド履歴へ保存しない。

## 容量と環境変更

確認時のCドライブ空き容量は約65.1 GiB。WSL、Ubuntu、Swift、xtool、Xcode 26のXIP、展開中の一時領域、生成したSDKを同時に保持する正確な必要量はまだ確定していない。Appleへのログイン前に取得ファイルの正確なサイズを確認できていないため、この空き容量で十分とは判断しない。

次の環境変更には、管理者権限を伴うWSLとUbuntu 24.04の導入、再起動、Linux利用者の初期設定が含まれる。その後、Swift 6.3.3とxtool 1.17.0を導入する。Xcode 26の取得と`xtool setup`はApple Accountの操作を伴うため、認証情報を扱わない形でユーザー操作と切り分ける。

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
