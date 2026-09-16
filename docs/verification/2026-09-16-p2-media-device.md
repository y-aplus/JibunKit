# P2-C 音声・撮影の実機確認（未確認）

source `306874f232849fa81de20985f3e2f90bf2da5a09`、0.8.2/build12。CI35090872646で通常版と診断26件・診断IPAが成功。実機確認後に版を進める。

[診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-c-device-check-20260916/JibunKit-P2-C-306874f.ipa) ／ [診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-c-device-check-20260916/JibunKit-P2-C-306874f.zip)

[戻す通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-c-device-check-20260916/JibunKit-normal-306874f.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-c-device-check-20260916/JibunKit-normal-306874f.zip)

アプリを削除せず上書きする。各ZIPの中身は同名IPA一つ。管理・復元の組合せ、再インストール、Refreshの反復は求めない。1〜4は会話でも一まとまりずつ案内し、個々の返答ごとにはpushしない。異常時は該当画面の文言と操作だけを記録する。まだ全項目未確認。

## 1. 再生・背景・OS操作

「Audio Player」→「ローカル音声を再生」。音が鳴ることを確認する。

画面をロックする。音が続き、ロック画面の再生操作に「JibunKit Loop Tone」が出ることを確認する。そこで一時停止→再生を各一回。音もその操作に従うことを確認する。

アプリへ戻り、Siriなどで一度音声へ割り込んでから戻る。「ローカル音声を再生」で再開できることを確認する。最後に「ユーザー停止」で止める。

イヤホンが手元にあれば、イヤホンで再生→接続を外す操作も一回。外した直後に勝手に再生を続けないことを確認する。手元になければ経路変更だけ保留と伝えればよい。

## 2. 実録音

管理画面で「Audio Recorder」のマイク利用を「許可」にする。

「Audio Recorder」→「録音開始」。iOSが聞いたらマイクを許可し、3秒ほど話す。

「録音停止して再生」で自分の声が聞こえ、表示のsamplesが0より大きいことを確認する。最後に「録音資源を解放」。

## 3. 写真・音声付き動画

管理画面で「撮影Probe」のカメラ・マイク利用を「許可」にする。

「撮影Probe」→「実写真を撮る」。iOSの許可後、写真が表示され成果が増えることを確認し、「停止」を押す。

「Audio Player」で再生を始め、「撮影Probe」へ戻り「音声付き動画」。短く話し、ホーム画面へ出てから戻る。録画が終了し、保存または失敗の結果が表示されることを確認する。保存されたら「保存した動画を共有して確認」から対応アプリで映像と声を確認する。部分成果の失敗表示が出た場合は、その文言を報告する。成功へ読み替えない。

「Audio Player」の再生も最後に「ユーザー停止」で止める。写真/動画は成果確認用の一時データで、backupや上書き保持の確認対象ではない。

## 4. 文書・QR

管理画面で「Scan Probe」のカメラ利用を「許可」にする。

「Scan Probe」→「文書scanner」。紙を1枚撮って保存し、戻った画面に文書画像と成果件数が出ることを確認する。もう一度開いて取消し、閉じられることを確認する。

「code scanner」で手元のQRを読み、戻った画面に内容が出ることを確認する。QRが手元になければこの項目だけ保留と伝えればよい。「利用不可」が出た場合は全文を報告し、対応端末/OSの制約と実装不具合を分けて判断する。

すべて終えたら各画面の音声・録画を停止して通常IPAへ戻せる。Counter/Reminderの既存データが見えることを一度確認する。Widget/Shortcuts/選択復元の全項目を繰り返す必要はない。

## 自動試験との境界

共有359件（既存Keychain2skip）とnative26件（skipなし）が成功。互換/非互換音声要求、失敗・取消・遅着・世代・片側停止と他owner保持、実Feature lifetime、共有capture/audio接続、SDK raw値、UIKit提示の所有を自動確認済み。文書SDK非対応時は実controllerを作らず拒否する。提示所有の試験では通常UIViewControllerを注入しており、実VisionKit画面や実scan成功の証拠ではない。

実機の結果は上の各項目へまとめて追記する。未実施や観測できなかった項目を成功にしない。過去のLive B単発差分は今回の結果で解決扱いしない。
