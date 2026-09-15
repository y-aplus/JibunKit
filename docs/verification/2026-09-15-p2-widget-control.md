# P2-W 操作Widget/Controlの実装・検証

開始点はmain df43dac（0.8.0公開後にIssue #6を正式採用）。[開始契約](../delivery/P2-widget-control-contract.md)に設定/操作・app-extension整合・管理・OS接続・ガイドを一括した。P2-7は未完。

## 基盤実装

MiniAppSharedStateは小さなFeature所有Codable状態を選択的にapp/extensionへ共有する。owner別NSFileCoordinatorと原子的保存で、読込みから更新・受付停止・削除までを同じ調停先へ接続する。削除のtombstoneと置換世代で、古い操作の復活を拒否する。破損・未初期化を初期値で上書きしない。既存のUserDefaults/DBをこの方式へ強制せず、業務モデルはFeatureへ残す。

9件のnative試験に片側更新/別instance再読出し、変更途中throwの元byte保持、無効化/再有効化、削除/再登録と古い世代、復元世代、破損拒否、owner不一致、optional nil、未初期化拒否を追加した。別macOS processのprobeでは300並行更新、管理closeと進行中更新の順序、Aが保持中のB進行、writer kill時の未commit/lock解放、tombstoneと古い世代拒否を確認する。

通常管理・復元・Widget/Controlへの接続、Swift native実行はこの記録開始時点では未完。公開0.8.0へ追加した機能ではない。

## 最初のCIを事前probeにする理由と予算

最初の1runは、app/Widget/Controlの三入口が依存する別processの調停方式を確かめる事前probeとする。NSLockを増やすだけでは成立しない問題であり、実OSのファイル調停とプロセス終了が成立しない場合は後続三入口の保存設計を変える必要がある。in-process mockだけでは判定できない。境界の初回2run予算の1回に数え、子提出や小APIごとには実行しない。

workflow build-ios.ymlをこのbranchのimmutable SHAからdispatchする。入力はsimulator_tests=false、feature_validation=false、records_validation=true、その他default。共有全試験と新9件、macOS別process probe、通常Release/native metadata/署名/IPA/Recordsをまとめる。UIは今回は動かさず、Widget/ControlのOS成功を主張しない。

直近同等入力34967147135はrun5分16秒/job5分4秒。新試験/helper build/300 file更新と複数process起動に約2〜4分、既存準備/通常build/upload込み約8〜10分を見込み、上限目標30分へ余裕がある。job依存の追加やserial Simulatorはない。probeが失敗したらまず全ログを集め、3失敗より前でも型/ファイル調停/fixtureを切り分ける。

後続の候補runは通常接続・native metadata/独立/統合・設定/操作OS試験を一括する。具体的filterと25分以内の並列job設計をその投入前に固定し、P2全体のpreflight/evidence gateを通す。初期probeの成功だけでP2-7をcompleteにしない。probeと後続sourceが異なること、再利用する試験と差分を明記する。

ローカルではdelivery 19件を含むTools全71件が成功した（11.232秒）。このWindows環境にSwift/Xcodeはなく、新Swiftの実行はCI待ち。

## 事前probe投入

[CI34975495965](https://github.com/y-aplus/JibunKit/actions/runs/34975495965)を投入し、headSha=`b6244de6635d56969e1eceb94f35282d0dca096b`、in_progressを確認した。run数は1（初回2run予算）。GitHubのdispatch APIはSHAをrefとして拒否したため、同じSHAへ固定したbranch `codex/p2-widget-control`をrefとして使った。拒否された要求はrunを生成していない。作業継続用branchは`codex/p2-widget-integration`に分け、実行中refを動かさない。

既存のOS完了監視を登録し、一回だけqueueへ結果を送る。モデルによる定期確認やgh run watch --intervalは使わない。結果待ちの対象は上記run。製品コードはmainへ未統合で、次はこのOS調停結果を確認して通常管理/復元とWidget/Controlへ接続する。
