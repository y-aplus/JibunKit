# 大きなCI単位の準備・検証

更新日: 2026-09-14。対象は[5つのCI境界](implementation-priorities.md)。計画の正本は[plan.json](delivery/plan.json)。
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
Simulatorまたはdeviceのどちらでも証明できるOS条件を実機で確認する場合、`planned_device_checks`へcriterion、候補の40桁source、checkpoint、具体的procedureを記録する。これはpreflightの実施予定にだけ算入し、ci/release gateは実測のpassed evidenceがなければ通らない。CIだけで証明すべき条件の先送りには使えない。
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

2026-09-14のユーザー指示により、遅くとも3回の失敗を目安に切り分けを実施する。同じ受入条件の再試行を数え、途中の無関係なjob成功やworkflow/branch変更で回数をリセットしない。同じ症状が続く場合や観測が不足する場合は3回を待たずに行う。必要な試験へ到達できなかったtimeout/cancelも、同じ停滞の評価に含める。

次の高コスト再実行前に、関係run・最初に失敗した工程・成功済み範囲・残る仮説・仮説を区別する観測を境界記録へまとめる。既存ログで区別できなければ、標準APIとの比較、最小host、個別のbuild/試験等の小さい検証を先に行う。待機上限の延長だけを切り分け実施と数えない。目的は原因を区別することで、3失敗ごとの新しい専用CIを機械的に増やすことではない。

- 全失敗を契約・実装・試験・環境に分類し、一度に修正する。同じ原因の小修正ごとに新しい全CIを起動しない。
- source不変の環境失敗は失敗jobだけの再実行を使える。run/attemptと原因を記録する。
- code変更後は新SHAの影響試験と必要な共有回帰を実行する。無関係な既存証拠は差分レビュー付きで再利用する。
- assertionを弱めて緑にしない。共通契約・データ所有権・期待動作を変更したときはCI前に一括再レビューする。
- 独立した成功jobの結果は保存し、全runの再実行を既定にしない。

CIの完了待ちはOS側の監視とqueue通知へ任せ、モデルpollや`gh run watch --interval`を使わない。

### P1の端末単体診断候補

`p1_device_validation=true`はP1-A/P1-Bの診断Featureを同じRegistryへ組み込み、端末内HTTPを選び、network jobで診断IPAを生成する。`generated_validation_only=true`、`split_generated_ui=true`、`simulator_tests=true`、`feature_validation=true`、`records_validation=false`と、HTTP/通知/Webを含む明示的method一覧が必要。Recordsを省略する場合は既存成功sourceからの差分を記録する。

P1候補IPAは`verify-p1-device-ipa.py`で版/識別子、Widget kindとextension内resource、CRCを検査しinventoryを添付する。これはOS gallery露出の証拠ではない。`P1WidgetGalleryUITests`を含む場合、通常Counter-only hostを先に同じbundle/versionでinstall/launchし、そのまま診断構成へ上書きしてgalleryと描画を確認する。

二jobは同じ全Feature構成をbuildし、`split-generated-ui.py`が実行methodだけを分ける。HTTP+通知はnetwork、残りはweb-management。少なくとも一つの未実行/変更後の条件を検証するために起動し、run表示を緑にするだけの再実行はしない。

専用端末HTTP XCTestは`p1_device_http_validation`のdefault=trueで実行する。fixture Swift・XCTest・専用Project・runnerに変更がなく、既存runの個別passとartifactを照合したときだけfalseで再利用できる。診断IPA生成を無効化する入力ではない。fixture試験成功を通常host UIや実機の成功へ拡大しない。

macOS標準Bashの`set -u`では空配列の展開も失敗し得るため、optionalなコマンドprefixは非空の`env`を既定とする。引数・環境変数・終了コードの受渡しは`test_workflow_command_prefix.py`で検証する。ローカルBashでの検査とmacOS CIの結果は分けて記録する。

### 実機NG後のnative入力切り分け

`native-surface.yml`の`surface=p1-input-repair`は、既存incoming/intents runnerを独立jobとして一runで実行する。通常IPAやgalleryを検証したとは扱わない。目的・再利用・次の候補境界は[2026-09-15記録](verification/2026-09-15-p1-device-followup.md)を参照する。

## マイナー版の文書・出荷gate

### 文書の正本と履歴

- P単位の現在状態・残作業・到達条件は`docs/delivery/plan.json`を正本とする。優先順位文書は版境界/順序、D台帳は統合差分の範囲/残件、statusは公開版・main・開発branchの要約を持つ。同じ進捗表の多重保守を避け、詳細へリンクする。
- guidesは現在のAPI/接続手順/制限、CHANGELOGのUnreleasedは未公開変更を示す。新しい実装や検証結果で記述が変われば同じ変更のまとまりで同期する。
- 境界のevidence JSONはrun/source/操作/結果/再利用理由を保持する。日付付き検証記録は経過と判断理由を保持し、先頭に現在の要約と過去記録の時点を示す。過去の失敗や取消は書き換えない。
- 独立作業用の文書branchはCI中の一時的な編集先とする。CI終了後に統合し、別の恒久的正本にしない。主張する状態が公開版/main/開発branchのどれかを明記する。
- 過剰な必須手順を見つけた場合は、負担・失う保証・代替策を示して廃止/変更を提案する。承認前に黙って検査を省略せず、ツールと手順が食い違わないようにする。

各minorで現在状態を示す文章を全件読み直し、機能、制約、未対応、手順、公開版/main、証拠sourceを同期する。
`README`や日付だけの変更では満たさない。対象一覧は次で動的に列挙する。

```powershell
python Tools/check-delivery.py --list-docs 0.7.0
python Tools/check-delivery.py --report .git/P0-C.json --stage release --release 0.7.0
```

対象はrootのREADME/CHANGELOG/CONTRIBUTING/SECURITY/notice、docs直下、全guides、deliveryの説明、Module README、現在の完成計画と当該release notes。
履歴・過去release notes・日付付き実験結果は現在状態へ改変せず、訂正が必要なら注記する。
新たに別の場所へ現在文書を追加した場合は`current_docs`の探索範囲も更新する。

2026-09-14のユーザー承認により、文書ごとの理由・SHA-256の重複記録を廃止する。全件の読了確認は維持する。
`documents`に各`path`、`outcome`（updatedまたはreviewed-unchanged）を入れる。
`document_review`には`source`（確認した40桁Git commit）、`summary`（修正内容と更新・非更新の理由をまとめた説明）、`unresolved`（未解決事項の文字列一覧、なければ空配列）を記録する。理由は関係する文書群でまとめられ、各ファイルで繰り返す必要はない。未解決事項は出荷判断で扱い、現在状態の誤記を未解決欄に移すだけで出荷可とはしない。
文書を読み直して必要な修正をcommitした後、そのcommitを確認記録へ書く。toolは全対象の一覧・結果と、確認commitに各文書が存在し現在の内容と一致することを検査する。文書編集後は変更箇所を再確認し、確認commitと一覧・まとめを更新する。記録自体は日付付き検証資料へ置けるため、commitの自己参照は不要。
一覧やcommitを自動入力するだけでは読了扱いにしない。構造検査は内容の更新漏れを意味的に判定しない。日常の実装・検証結果の同期と、minor出荷時の全件レビューは両方必要である。
0.7.0の個別理由/hashを含む過去記録は変更せず保持する。当時のgate再現には当時のcommitのtoolを使い、今後の出荷で旧形式へ自動的に後退する経路は設けない。IPA等の配布物digestや証拠の`reuse_reason`はこの廃止の対象外。
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


## 通常・生成hostの並行実行

P1-A run34794545131は全試験・artifact upload終了後に45分timeoutとなった。通常UI12.1分、Files3.7分、生成host7.9分、Records4.0分の実績があり、30分の直列見込みは成立しなかった。

`feature_validation=true`、`simulator_tests=true`、通常UI filter空、focused=falseの場合、同じrunのbuild matrixをnormal/generatedの二jobに分ける。normalは共有tests、通常IPA、Counter、backup harness、通常UI/Files。generatedはFeature生成/Release・単独/統合UI・Records UI。native Intents/Widget/incomingの専用jobは従来どおり独立する。build-onlyやfocused呼出は従来のcombined経路を保つ。

fail-fast=falseで兄弟jobを取消せず、生成jobのartifactには`-generated`を付ける（例: `JibunKit-simulator-evidence-generated`）。通常IPA名は`JibunKit-ad-hoc`のまま。Recordsは通常UIの成否ではなく自身のtemplate workspaceとSimulator準備の成功に依存する。P1-B run34802338245でnormalは33.82分で成功し、旧29分見込みを超えた。generatedは26分で失敗し、P1 UIは未開始のため正常所要時間の実績ではない。両方45分が上限。次の全体境界ではこの実績を使い、旧見込みをそのまま転用しない。

通常実装を変えず、生成host/Records UIや試験準備だけを直す場合は`generated_validation_only=true`で再検証する。`feature_validation=true`、`simulator_tests=true`、通常UI filter空、focused=falseが必須。通常job、Feature build requirements、Notes単独UIを省略し、生成hostの作成/Release build、指定した生成host UI、Records build/UIは実行する。省略対象の成功run/sourceと差分の再利用理由を検証記録へ残す。未成功・変更済み対象を省略する用途には使わない。nativeオプションは独立jobとして同じrunで実行できる。

`records_validation`は既定trueでRecords単独build/UIを含む。成功済みのRecords実装・試験が変更されていない再検証では、証拠のrun/sourceを記録してfalseにできる。P1-B run34806399426のRecords成功以後のUI fixture修正に使用する。通常のFeature全体検証では既定trueを維持する。

run34808525786では10 UIが全成功したが、試験自体33.03分、host step38.28分、準備/証拠出力込み46.53分となり45分上限でcancelledになった。次のP1統合では`split_generated_ui=true`、`generated_validation_only=true`、`records_validation=false`を指定する。一つのrun内でnetwork（HTTP+通知、実測15.40分）とweb-management（Web+P0、実測17.63分）の二jobへ分け、準備/証拠出力を含め約24/27分を見込む。job上限45分は延長しない。

生成するhost/Registryは両jobで同一の全入力を使い、実行するmethodだけを`split-generated-ui.py`で分配する。分配は重複/欠落/空shardを拒否し、method単位を必須にする。artifactに`-generated-network`/`-generated-web-management`を付けて衝突を避ける。これで総runner時間には準備分の追加があるが、同じ長いjobのtimeout・再試行を避ける。完了通知はrun単位の一回で、子担当のCIは増やさない。分割の初実行は次の必要な診断候補変更と合わせ、表示だけをgreenにするための再実行はしない。

追加のnativeオプションや長い生成selectorを付ければこの見込みを再利用しない。P1-Bの事前契約でnative Web認証等を別jobへ出し、各job30分以内の実績に基づく計画を作る。runの見かけだけをgreenにする目的で、成功済みのP1-A全試験を即座に再実行しない。

P1-B候補では`web_authentication_validation=true`を`native-surface.yml`の独立jobへ移し、通常IPA/UIと直列にしない。上限30分。診断artifactは`Native-web-authentication-diagnostics`で、従来のlogとxcresultを保持する。生成hostのHTTP/Web/通知は`prepare-p1-b-host.py`が選択されたペアだけを通常Registryへ接続し、入力の全検査が通るまで書込みを始めない。これらの新しい経路の初回実動はP1-B統合CIで検証する。


### P1実機後の集中候補境界（2026-09-15）

診断IPAの収録範囲をUI filterから切り離した。`p1_device_validation=true`はP1-A/IncomingとP1-B全ペアを必ず接続する（Bは`--all-lanes`）。既存B-onlyの生成はfilter選択を維持する。候補はexplicit method selectorを必須とし、通常/生成の二jobでも実行可能。長い全P1 UIを回す場合は既存splitを使い、成功済み範囲の再利用はrun/sourceと差分理由を境界記録へ書く。splitなしはgenerated job、split時はnetwork jobが診断IPAを出力する。filterを減らすことで配布物からFeatureが消える状態を防ぐ。

共有入力/Intent/Widgetの4件に絞った境界ではsplitを使わず、通常回帰+IPAと並行する。通常hostの実UI成立を確認してから同じID/versionの診断hostへ削除なしで置換し、galleryを確認する。IPA inventoryのkind/resource収録成功だけでgallery成功を代替しない。詳細な入力・再利用範囲は[実機後の記録](verification/2026-09-15-p1-device-followup.md)に固定する。


`native-surface.yml surface=incoming-os`はP1実機後の共有エラー切り分け用。tracked sourceから通常host+受信A/Bだけを構成し、OS共有の文字列/URL/ファイルを独立methodで観測する。未実行の他形式を最初の失敗で隠さない。通常版/完全P1 candidate/実機受入の代替にはしない。typeと工程のみのDebug診断をxcresult/logへ保存する。詳細は[実機後記録](verification/2026-09-15-p1-device-followup.md)。


`surface=incoming-repair`はincoming native回帰とincoming-osを独立jobで一runへまとめる。plain-text受信の修正確認用で、Intent/Widget/通常IPAは再実行しない。OS3件はFeature取込み内容まで照合する。最終の完全host/実機確認は別の未完条件として保持する。
