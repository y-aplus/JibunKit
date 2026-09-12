# 大きなCI単位の準備・検証

更新日: 2026-09-12。対象は[5つのCI境界](implementation-priorities.md)。計画の正本は[plan.json](delivery/plan.json)。
この手順は小変更ごとのCI・親子レビューを置き換える。試験を一つの巨大な直列jobへ詰め込む指示ではない。

## 境界を開始する前

1. 対象waveのP単位、親D、合格条件、前提wave、対象外を読む。既存成果を使い、残る通常接続を明示する。
2. [並列運用](parallel-implementation.md)に従い共通契約と担当を一度揃える。
3. 合格条件ごとに、実行する操作と観測値をtest名・fixture・通常画面へ対応付ける。二ownerの片側取消/失敗/削除と他方維持を含める。
4. 以下のテンプレートを作り、空欄を埋める。記録は当初`.git`等で編集し、証拠完成時に`docs/verification`へ移す。テンプレート生成は合格を意味しない。

```powershell
python Tools/check-delivery.py
$candidateSha = git rev-parse HEAD
python Tools/check-delivery.py --template P0-A --source $candidateSha --output .git/P0-A.json
python Tools/check-delivery.py --report .git/P0-A.json --stage preflight
```

`contract`にはbaselineの40桁SHA、interface、ownership、failure_cases、normal_entrypoints、invalidation、reviewを記録する。
文章本体でも、その内容を確認できる文書/レビューへの参照でもよい。`dependencies`には先行waveの確認記録を入れる。
契約レビューが未完ならpreflightを通さない。

## CIの分割と実行

初回予算はP0各境界2 run、P1各境界3 run。通常host/IPA/主要UIと生成host/独立Feature/対象native比較を分ける想定で、必要のないrunを消化しない。
既存workflow inputとtest filterを利用する。着手時に使用する正確な入力組合せと対象testを記録し、`full`相当の指定で全native試験が動くと推定しない。
現workflowは主に`workflow_dispatch`で、チェックポイントpush自体はCI境界にならない。

一jobの見込みを30分以内、timeoutを45分以内とし、既存のより短い上限は維持する。
見込みを超える場合は共通buildの再利用、並列job/試験群分割を**最初の実行前**に設計する。
run予算とjob上限が両立しない場合は根拠を記録してrun予算を増やす。試験を削って予算へ合わせない。
実装前のOS挙動確認が複数レーンの設計を左右する場合だけ、関連する疑問をまとめた事前probeを予算に含める。

`jobs`は次の形で合格条件へ対応付ける。これは手動実行/既存CIの実行計画であり、ツールは任意commandを実行しない。

```json
{
  "id": "lifetime-unit",
  "kind": "unit",
  "criteria": ["P0-1.lifetime"],
  "command": "実際に使うコマンドとtest filter、またはworkflow名と全入力値",
  "expected_minutes": 10,
  "timeout_minutes": 20
}
```

`kind`はunit/simulator/inspection。deviceはCI jobへ割り当てない。planの`kinds`は許容する証拠種別の選択肢で、記載種別を全部実行する意味ではない。
`planned_ci_runs`へ予定run数を入れ、超過は`budget_exception`へ理由を入れる。
全体をレビュー後、CI用branchのHEADを固定し、同じ40桁sourceでdispatchする。各runのheadShaを照合する。
実行中に同branchを動かさず、独立作業は別branchで進める。

## 証拠と実機の区切り

合格条件ごとに`evidence`へ次を一件記録する。複数test/runは一件のreferenceにまとめた検証記録へリンクする。

```json
{
  "criterion": "P0-1.lifetime",
  "kind": "unit",
  "source": "実際の40桁commit",
  "result": "passed",
  "reference": "run URL、artifact/log、該当test名を記録した文書",
  "observation": "実際の操作と結果。取消したAの解放後もBが継続した等",
  "review": "契約・操作・assertion・出力を照合したレビュー記録"
}
```

古い証拠はsourceを変更せず、`reuse_reason`に候補までの差分と依存を確認して影響がないとした理由を記録する。
主張する操作の実行ログがないbuild成功、直接performの成功だけでOS Shortcuts成功、部分filterで全回帰成功とはしない。
`runs`には全実行を`id`（run ID/attempt）、`url`、`source`、`conclusion`で残す。失敗・取消・再実行も数える。
過去の失敗runを残してもよいが、現在の合格条件は全て成功証拠で閉じる。

```powershell
python Tools/check-delivery.py --report .git/P0-A.json --stage ci
```

途中のwaveではdevice専用条件だけを`deferred_device`で対応minorへ予約できる。
P0-A/Bでは0.7.0、P1-Aでは0.8.0の候補にまとめる。CI合格でもそのP単位は実機未確認のままcompleteにしない。
P0-C/P1-BのCI確認後、minor出荷gateを通すには全条件を閉じ、延期欄を空にする。
過去の実機証拠を再利用する場合もsource/差分レビューを必須にする。実機でしか決められない設計上の疑問が全体を止める場合は中間確認をまとめて依頼できる。

## 失敗後の再実行

- 全失敗を契約・実装・試験・環境に分類し、一度に修正する。同じ原因の小修正ごとに新しい全CIを起動しない。
- source不変の環境失敗は失敗jobだけの再実行を使える。run/attemptと原因を記録する。
- code変更後は新SHAの影響試験と必要な共有回帰を実行する。無関係な既存証拠は差分レビュー付きで再利用する。
- assertionを弱めて緑にしない。共通契約・データ所有権・期待動作を変更したときはCI前に一括再レビューする。
- 独立した成功jobの結果は保存し、全runの再実行を既定にしない。

CIの完了待ちはOS側の監視とqueue通知へ任せ、モデルpollや`gh run watch --interval`を使わない。

## マイナー版の文書・出荷gate

各minorで現在状態を示す文章を全件読み直し、機能、制約、未対応、手順、公開版/main、証拠sourceを同期する。
`README`や日付だけの変更では満たさない。対象一覧は次で動的に列挙する。

```powershell
python Tools/check-delivery.py --list-docs 0.7.0
python Tools/check-delivery.py --report .git/P0-C.json --stage release --release 0.7.0
```

対象はrootのREADME/CHANGELOG/CONTRIBUTING/SECURITY/notice、docs直下、全guides、deliveryの説明、Module README、現在の完成計画と当該release notes。
履歴・過去release notes・日付付き実験結果は現在状態へ改変せず、訂正が必要なら注記する。
新たに別の場所へ現在文書を追加した場合は`current_docs`の探索範囲も更新する。

`documents`に各path、`outcome`（updatedまたはreviewed-unchanged）、確認理由`reason`、確認済み内容の`sha256`を入れる。
hashだけを自動入力して読了扱いにしない。追記なしでも既に正しい文章は理由付きで維持できる。
文書編集後に古いhashの確認記録は失効する。改行を含む実ファイルのhashなので、実際の候補checkoutで確認する。
`release`にはcandidate_ipa、normal_regression、generated_host、metadata、compatibility、physical_reviewの証拠参照を入れる。
planの対象単位をcompleteにする前に証拠をレビューし、[公開手順](releasing.md)の候補/公開後の二段階で文章を同期する。
0.8.0ではP0も維持している証拠が必要。1.0は需要調査後のユーザー決定とgate更新まで通らない。

このツールはローカルの必須手順でありGitHub branch protectionや自動公開を設定するものではない。
検査するのは計画構造・証拠の網羅/種別・source再利用理由・文書の確認漏れ/変更後失効。
ログの真偽や文章内容の正しさ、scope内の全シナリオは担当と親が確認する。成功メッセージだけで公開しない。

```powershell
python -m unittest discover -s Tools/tests -p test_delivery.py -v
```

`metrics`のreview_rounds/parent_messages/ci_job_minutesは全担当の実数を集約する。
最初のP0-Aと各minorで比較し、管理コストを含めた運用改善を判断する。
