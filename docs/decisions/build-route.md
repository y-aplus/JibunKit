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
- 次に、公式の取得元、対応版、利用条件、必要容量、Appleへのログインが必要な箇所を確認する。
- 調査結果と必要な環境変更を説明してから、WSL・Swift・xtool等のインストールへ進む。
- GitHub Actionsのクラウド経路は、ローカル経路が許容範囲で成立しない場合だけ検証する。

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
