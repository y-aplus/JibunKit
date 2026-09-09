# 共存の制約とJibunKitの未対応

2026-09-09。ユーザー判断により現状は1.0未達。基準は、JibunKitを知って開発を始めれば幅広いSwiftアプリを機能を削らず共存させられること。サンプルの成功は接続の部分的な証拠であり、完成基準の上限ではない。

## 判定規則

- OS・署名・単一プロセスの条件と、その条件下で実装できる調停を分ける。
- 複雑、利用例がない、個別に要求されていないという理由だけでは対象外にしない。基盤の製品目的から必要性を判断する。
- 未調査は未調査と記す。実装不在をOS制約へ分類しない。禁止や権限の可否はAPI・署名条件ごとに根拠を確認する。
- Integrationへの登録や標準APIの接続は必要でも、Featureごとのhost分岐、他Featureの内部理解、機能削減を通常手順にしない。
- 不正なアプリの修復や悪意あるコードの隔離は別問題。正しく接続したFeature同士の干渉は基盤が扱う。

## 初期棚卸し

| 領域 | 避けられない条件・外部条件 | JibunKitの改善対象 | 現在の証拠/不足 |
| --- | --- | --- | --- |
| クラッシュ・メモリ | 同一プロセス内の完全な障害隔離はない | 所有者別のタスク停止・解放、メインスレッドを塞がない契約、資源消費の診断 | 保存処理の限定検証のみ。共存時の負荷・解放は未検証 |
| 音声 | AVAudioSessionはアプリ共有。相容れない同時要求は調停が必要 | 所有権、競合結果、中断/復帰、録音と再生の共存、Now Playing/remote commandの対象切替 | 接続・調停とも未実装。音声アプリを対象外にする理由ではない |
| 起動・復帰 | アプリのライフサイクルを共有する | 画面未表示のFeatureにも必要なイベントを配る、重複抑止、終了契約 | 個別ViewのscenePhase利用のみ。共通登録口なし |
| バックグラウンド | 実行時刻・時間・許可はOSが管理 | task登録の集約、ID衝突検出、適切な所有者への配送、期限切れ/取消、background URLSessionの再接続 | 未実装。OSが時刻を保証しないこととは別 |
| URL・認証・ファイル受信 | ホストのURL登録・OS配送口を共有する | callback所有者の特定、衝突/曖昧性拒否、受信ファイルの権限と寿命、user activityの配送 | 固定mini-app URLと通知詳細は実装済み。一般callback/importは不足 |
| 権限・capability | OS上の許可と署名で使用可能な機能に従う | Feature要求を宣言・合成し、衝突や不足をビルド時に説明。拒否時も他Featureを継続 | 手動Project編集中心。SideStoreで使えないcapabilityを一括推定しない |
| 状態・保存・認証情報 | app sandboxを共有する | 保存/Keychain/cookie/cacheの所有範囲、意図しない共有を避ける既定値 | 保存namespaceと選択復元は検証済み。他の共有状態は未調査 |
| 依存ライブラリ | 同じビルド内で依存解決する | 衝突診断と解消手順、global delegate/singletonの接続整理 | Package構成のみ。複数SDKの共存は未検証 |
| UI・提示 | sceneごとの表示面、向き等の条件を共有 | Featureの遷移状態保持、提示の所有権・競合、UIKit接続、複数sceneの扱い | SwiftUI NavigationStack中心。広いアプリ構成は未検証 |
| Widget・extension | extensionの種類・権限・実行条件はOSによる。別processのextensionもある | 定義の合成、ID/保存/更新の所有範囲、必要targetへの接続 | Counter一例のみ。『1アプリなので全て同一process』と一括説明しない |

この表は実装調査の初版で、網羅性の保証ではない。カメラ・位置情報・Bluetooth等も権限、共有資源、background継続の観点で追跡する。単なるAPI wrapperを増やすのではなく、共存で必要な所有権と配送を実装する。

## 外部根拠

- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession): アプリの音声sessionはsingleton。だから調停が必要なのであり、複数Feature利用が不可能とはしない。
- [Choosing Background Strategies](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app): OSが実行機会を判断。登録とFeatureへの配送はアプリ側の責任。
- [App extensionの構造](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html): 本体とextensionを区別し、process共有の説明を対象に合わせる。

## 1.0再評価の条件

各領域で必要な接続、所有者、競合時の動作、失敗/取消/復帰を説明でき、独立に作った二つ以上のFeatureの共存で検証する。先にサンプルを作らないと着手できない手順にしない。未実装・未調査のまま『Feature側で対応』とだけ書いて完了にしない。外部制約には根拠、JibunKit側の不足には実装タスクを付ける。

## 最初の実装: ホスト活動状態の配送

MiniAppDefinition.onHostPhaseChangeへIntegrationを任意登録する。Appで観測したscenePhaseを、Root View生成の有無によらず全登録先へ届ける。初期状態と状態変化を配送し、同一状態の重複を抑止する。Feature表示中/非表示のイベントとは区別する。ハンドラは短い状態更新や非同期処理の開始に使い、同期の重い処理を置かない。この実装はBGTaskScheduler、終了猶予、タスク所有権、音声調停を提供するものではない。それらは引き続き未対応として追跡する。

検証: 二つの独立ハンドラに初期状態・復帰が配送され、重複イベントが増えないことをunit testで確認する。iOS hostへの接続はCIビルドで確認する。まだ結果待ちで、実sceneイベントの複数Feature共存UI検証は次のタスク。

既存の成果は将来0.2としてリリースすることをユーザーが容認。これは即時公開の指示ではなく、1.0完成条件の緩和でもない。旧1.0下書きは公開保留を明示して保持する。

CI 34315477769（34a5b01）は成功。初期状態・復帰・重複抑止を二つのハンドラで確認するunit testと、iOS通常/生成ホストビルドが成功。次にCI専用Integration二件を登録し、どちらの画面も開かず背景化・復帰した後に両者へ同じ履歴が届くUIテストを追加。fixtureは隔離checkoutだけへコピーし通常IPAへ含めない。実scene配送の結果は未確認。
