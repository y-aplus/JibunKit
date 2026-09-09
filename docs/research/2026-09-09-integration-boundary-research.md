# JibunKit 統合差分調査・実装引継ぎ台帳

調査日: 2026-09-09  
対象: `y-aplus/JibunKit` の取得時点の `main`、コミット `1b6ad200eba67733d75c791efd258cf6e7ac0bfc`  
作成: ChatGPT上のAIによる調査・技術提案。リポジトリの変更・Issue作成は行っていない。

## 結論

JibunKitの上位目標を弱める必要はない。対象は、独立アプリの境界で得られていた性質のうち、Feature化で失う差分を技術的に補うことである。必要なのは全iOS APIの再実装ではなく、所有者と寿命、共有入口の配送、共有資源の調停、状態の分離、ビルド時の設定/extensionの構成である。[R01]

調査では32の差分類型を整理した。これは全iOS APIの完全な監査済み宣言ではなく、境界から導いた調査・実装単位の台帳である。特に、helper extensionによる部分的な別プロセス化、アプリ単位の利用枠の統合、外部に見えるアプリidentity、標準の複数session/data store、Feature除去後の永続登録という点を追加した。

「複雑なのでlater」「サンプルがないので対象外」は判定に使わない。後述の順序は技術的依存と、不確かな前提が後続設計へ与える影響によるものであり、1.0の対象から外す提案ではない。

## 比較条件と根拠の扱い

比較対象は同じOS・端末能力・署名/アカウント条件で利用できる通常のサードパーティー独立アプリである。Apple純正アプリだけが持つ権限や、有料/特別entitlementのある比較対象を暗黙に混ぜない。対象ソースは最初からJibunKitの接続規則を知って開発するものとし、任意の既存アプリの無修正移植は要求しない。[R01]

標準形は一つのhost appと、用途に応じて組み込まれるextensionである。すべてを常に同一processと見なさない。App、process、scene、extension、service identity、instance、名前空間をそれぞれ分けて調べる。[R03, S01, S03, S42]

事実はApple/Swiftの公開資料および対象コミットのソース/記録に基づく。設計案と検証案はそれらからの技術的推論であり、新規機構をこちらでビルド・Simulator実行・SideStore実機検証したわけではない。文書のCI成功記録は記録として扱い、この調査での再実行成功とはしない。JavaScript依存のApple文書は取得できたAPI概要・検索結果と、本文を取得できたWWDC/アーカイブ/DTSで突合した。数値やavailabilityを取得できないAPIについて推測で確定しない。

## とくに重要な追加発見

### 1. 「同一プロセスでは不可能」と「iOS上で補完不能」は違う

Appleはenhanced-security helper extensionを文書化しており、Apple DTSは2025年11月にこの方式のTestFlight配布・動作を確認している。初期の非対応という回答だけを採用してはいけない。[S03, S04]

ただしSideStoreでの署名・起動、利用できる権限、寿命、hostとの通信、対象OS最低版はこの調査では実証していない。全Featureを別プロセス化する確定案ではなく、隔離可能性を決める優先検証である。まず小さな処理helperを起動し、終了・再起動とhost継続、次に対象機能に必要なAPIを確認する。実機で成立しない場合は、失敗条件を添えてその経路だけを制約として記録する。

### 2. 名前空間では利用枠を増やせない

CLLocationManagerのregion monitoringにはアプリごとの20領域上限がある。A/Bが各12件を必要とする例では、それぞれのアプリ上限内だった要求がhostでは24件になる。デバイス全体の上限もあるため、独立側の実行を無条件に保証する例ではないが、少なくともアプリ枠の統合という差分はある。[S23, S41]

同一条件の統合や優先度に応じた入替えは緩和になり得る。しかし全24件の同時監視と同等と記録してはいけない。別APIや方式の可能性は別途確認し、旧APIの数値を位置情報全体へ一般化しない。

### 3. 既存の分離機構を捨てる必要はない

WKWebsiteDataStoreの識別子付きストア、ASWebAuthenticationSessionの要求別completion、Core Bluetoothのmanagerと復元識別子、MPNowPlayingSessionの複数sessionを活かせる。JibunKitは必要な所有者割当・接続・取消を実装し、SDK全体を一つの自作singletonへ置換する必要はない。[S12, S13, S24, S22]

### 4. Widget/Intentの追加手順には改善余地がある

WidgetBundleで複数Widgetを一つのextensionへ含められる。また、AppleはSwift Package/static library内のApp Intents定義をサポートしている。現行の「Widget追加で別extensionが必要」「Intentをapp target内へ置く」という手順は、採用中の経路とOS上の必須条件を分けて書く必要がある。[R04, S27, S28]

## 台帳の読み方

「補完契約」は今回の設計提案。「現状」は限定したソース確認またはR01の状態記述。「残存制約」はその性質だけを対象とし、領域全体の除外理由にしない。現物で未検証の事項を「補完済み」「補完不能」へ繰り上げない。


## 差分一覧

| ID | 対象 | 主な境界 |
|---|---|---|
| D01 | ホスト活動状態・scene・Feature表示状態 | App / Scene / Feature実行単位 |
| D02 | タスク・購読・要求の所有権と取消 | Feature instance / Request |
| D03 | クラッシュ・ハング・メモリとhelper extension | Process / Extension process |
| D04 | 画面遷移・復帰・提示と複数scene | Scene / navigation container |
| D05 | 画面外観・idle timer等のアプリ共有設定 | Process / App / UI containment |
| D06 | UserDefaults・通常ファイル・DB配置 | App data container / Feature namespace |
| D07 | 復元・移行・リセット中の処理停止 | Persistent state / operation lifetime |
| D08 | Keychainと資格情報の削除範囲 | Signed access group / item namespace |
| D09 | URLSessionのcookie・認証・cache | Session object / App shared defaults |
| D10 | WKWebViewの永続Webデータ | Website data store |
| D11 | Web認証セッションと返却先 | Authentication session / App identity |
| D12 | URL・Universal Link・外部ファイル受信 | OS app/scene entry point |
| D13 | 通知カテゴリ・action・foreground・取消 | UNUserNotificationCenter / App |
| D14 | APNs・remote pushの配送とサーバー識別 | Signed App / APNs topic |
| D15 | BackgroundTasksの起動登録・期限・completion | App launch / BGTask identifier |
| D16 | Background URLSessionの再接続 | Background session identity / Process restart |
| D17 | ユーザー起点の継続処理・進捗・取消 | BGContinuedProcessingTask / App UI |
| D18 | Spotlight・NSUserActivityと項目削除 | App search index / App or Scene entry |
| D19 | 権限・プライバシー同意の単位 | OS authorization principal / Feature consent |
| D20 | 署名capability・Info.plist・構成の合成 | Build / signed entitlement / target |
| D21 | AudioSessionの構成と中断・復帰 | App audio session / Device arbitration |
| D22 | Now Playing・remote commands・再生対象 | Playback session / System media UI |
| D23 | カメラ・AR等のcapture資源 | Capture session / physical device / App state |
| D24 | Bluetooth managerの復元と接続所有者 | Manager instance / restore identifier |
| D25 | 位置情報・監視条件とアプリ単位の枠 | Manager / App quota / Device |
| D26 | Widget・Control・既存extensionの組立て | Containing app / Extension target and process |
| D27 | App Intents・App Shortcuts・メタデータ | Build-time metadata / App identity / execution process |
| D28 | Live Activities・AlarmKit等のシステム継続表示 | Activity / Alarm ID / App authorization |
| D29 | 依存ライブラリ・runtime globals・resources | Package graph / Process / Resource bundle |
| D30 | 外部サービスidentity・CloudKit・データ出所 | Signed App identity / Service container |
| D31 | 無効化・削除・更新・privacyの集約 | Feature inventory / App deployment |
| D32 | 補完不要な局所処理の識別 | Feature local objects / unchanged system-wide behavior |

## 各差分の評価

### D01 — ホスト活動状態・scene・Feature表示状態

**独立時の境界・主体:** 独立アプリには各アプリの活動状態があり、sceneにはsceneごとの状態がある。アプリが状態を保存したり不要な処理を止めたりする責任までOSが代行するわけではない。

**統合で失う差分:** JibunKitがactiveでも、Feature Aは未表示・非表示・複数画面の一部であり得る。ホストの状態を全員に配るだけでは、個別Featureの表示や終了を表せない。

**補完契約・実装案:** hostPhase、scenePhase、Featureの表示状態、明示的な開始/終了を区別する。非表示でも継続する処理は宣言して維持し、非表示を一律に終了へ変換しない。

**残存制約・未確定点:** OSが実際に与えるプロセスの実行機会は共有される。内部の状態通知でOSの別アプリを作れるわけではない。

**必要な検証:** A未表示/B表示、Aを閉じB継続、ホスト背景化/復帰、可能な環境で複数scene。各イベントの意味と配送先が一致すること。

**現状判定:** ホスト集約状態の配送は実装済み。二つの未表示Featureへの配送成功はR01に記録。Feature別の寿命管理は未対応。  
根拠: R01, R05, R09, S05

### D02 — タスク・購読・要求の所有権と取消

**独立時の境界・主体:** 独立アプリではプロセス境界によって他アプリのタスク集合と分かれる。Swift Task自体の取消は協調的で、独立アプリでも任意の処理が自動停止する保証ではない。

**統合で失う差分:** 共通プロセスでAを閉じてもAのTask、Timer、購読、callbackが残り、全取消をするとBまで止め得る。

**補完契約・実装案:** 安定FeatureID、実行インスタンスID、要求IDを区別する。タスクや購読を所有者へ登録し、その所有者だけ取消・解放する。閉じて再開した世代へ旧callbackを届けない。

**残存制約・未確定点:** 非協調コードの強制停止は同一プロセスの協調的な取消では実現しない。安全な別プロセス経路はD03で別評価する。

**必要な検証:** Aを取消、Bの同種処理を継続。A終了直後の遅いcallbackを破棄。画面を閉じても明示的な音声/転送処理は契約どおり継続。

**現状判定:** 未対応。onHostPhaseChangeの追加だけではこの差分は解消しない。  
根拠: R05, S02

### D03 — クラッシュ・ハング・メモリとhelper extension

**独立時の境界・主体:** 独立プロセス間にはアドレス空間と終了の境界がある。一方、デバイス全体の資源は元から共有で、他アプリが絶対影響を受けない保証ではない。

**統合で失う差分:** ホスト内のfatal error、unsafeな破壊、メインスレッド停止は複数Featureへ及ぶ。actorはプロセスの代用品ではない。

**補完契約・実装案:** 通常エラーのFeature別報告、資源解放、所有者別診断に加え、危険/高負荷な処理をenhanced-security helper extensionへ分離できるか評価する。公開APIとApple DTSの動作確認があるため、iOSだから不可能と打ち切らない。

**残存制約・未確定点:** 同一プロセス内の完全な障害隔離はできない。helper経路はSideStore/Personal Team、対象OS、extension lifetime、IPC、必要権限について未検証。全Feature UIをそのまま別プロセスへ移せるとは確認していない。

**必要な検証:** 同じ署名条件でhelperを起動し意図的に終了させ、ホスト/Bが継続するか、再接続できるかを調べる。実機導入・再署名後も確認。

**現状判定:** 協調的緩和は未対応。helperによる追加補完可能性は今回新たに発見した実装判断用の検証課題。  
根拠: S01, S02, S03, S04, S42, R01

### D04 — 画面遷移・復帰・提示と複数scene

**独立時の境界・主体:** 独立アプリは各自の画面ツリー・ナビゲーション状態・提示先を持つ。OSによる永続的な全状態保存は前提にしない。

**統合で失う差分:** 単一のNavigationPathをFeature切替で置換すると、別Featureの経路を同じオブジェクトで保持できない。共通singletonを複数sceneから使うと操作の所有sceneも曖昧になる。

**補完契約・実装案:** Feature実行単位ごとの経路/復帰契約とsceneを持つ提示窓口を設ける。SwiftUIだけでなくUIViewControllerを接続できる境界を持ち、内部UI構造を不必要に一律化しない。

**残存制約・未確定点:** 一つのsceneに同時に相容れない全画面提示を成立させる必要はない。競合の結果を定義する。複数sceneの対応範囲は端末とOSで分ける。

**必要な検証:** Aの詳細→Bの詳細→Aへ戻る、両者のsheet要求、通知から別sceneへ遷移。どの状態を保持/破棄するかを検証。

**現状判定:** AppNavigation.sharedに一つのpathがあり、open時に置換。Feature/scene別の一般的な保持機構は確認できない。  
根拠: R06, R09, R04, S05

### D05 — 画面外観・idle timer等のアプリ共有設定

**独立時の境界・主体:** 独立プロセスならグローバルな外観設定やアプリのidle timer設定は他アプリの同じ変数ではない。

**統合で失う差分:** Aが画面消灯を防止した後、Bが終了時に無条件で元へ戻すとAの要求も失われ得る。UIAppearanceの全体設定も他Featureへ波及する。

**補完契約・実装案:** 複数要求の取得/解放を管理し、有効な所有者が残る限り必要設定を維持する。外観にはUIAppearanceのcontainmentやview/scene局所設定を優先する。

**残存制約・未確定点:** プロセス全体の状態を自由に直接書き換えるSDKは、別設定/adapter/別プロセスの可否を調査する。全グローバル変数を万能に仮想化する機構は前提にしない。

**必要な検証:** A/B両方がidle timer無効化を要求しAだけ解放。Aの外観変更がBの画面へ漏れないこと。

**現状判定:** 初期台帳のUI領域に含めるべき具体的な未対応差分。  
根拠: S06, S07, R01

### D06 — UserDefaults・通常ファイル・DB配置

**独立時の境界・主体:** 独立アプリには別データコンテナがある。App Group等の共有は明示的な別条件。

**統合で失う差分:** 同じdefaultsキー、同じ相対パス、同じDB名を使うと衝突する。名前を分けても任意コードを隔離するOS sandboxは得られない。

**補完契約・実装案:** 安定したFeature namespaceと保存先を払い出す。DB技術はFeatureが選び、そのDBへ専用URLを注入する。共有する場合だけ明示的な共有ハンドルを渡す。

**残存制約・未確定点:** 同一プロセス内での論理分離であり、悪意あるコードに対する別sandboxではない。実データのファイル保護・バックアップ属性はデータ用途に応じて設定する。

**必要な検証:** A/Bが同じローカルキー・DB名を使用し、片方の更新/削除/再読込が他方を変えないこと。

**現状判定:** MiniAppContextのキー分離とMiniAppFilesの保存先は実装・限定検証済み。全保存API/DBの共存完了とは扱わない。  
根拠: R04, R08, S01

### D07 — 復元・移行・リセット中の処理停止

**独立時の境界・主体:** 独立アプリのデータ復元やリセットは別アプリの保存領域を対象にしない。ただし自アプリ内のDB整合性や処理停止は元からアプリの仕事。

**統合で失う差分:** JibunKitのまとめた復元操作がBの処理を止めたり、動作中AのDBを直接コピーして不整合を起こしたりする余地がある。

**補完契約・実装案:** 対象Featureだけを準備/停止/検証/置換/再開する契約を設ける。DB安全なsnapshotや移行はFeature adapterが提供し、ホストは所有範囲と全体手順を担う。

**残存制約・未確定点:** 任意DBの安全なバックアップを単なるファイルコピーで保証しない。Feature内の業務的なデータ正しさをホストが推測しない。

**必要な検証:** A復元中にBの保存が継続、A準備失敗でB不変、再開後に旧callbackが新データへ書かないこと。

**現状判定:** 選択復元の仕組み・証拠はある。全種DBと所有者別lifetime連携までの完成は未確認。  
根拠: R01, R02, R04, S02

### D08 — Keychainと資格情報の削除範囲

**独立時の境界・主体:** Keychainはアプリに許されたaccess group等でアクセスを制御する。明示的に共有可能なグループもある。

**統合で失う差分:** 同じホストの権限で同じservice/accountを使うと衝突する。広いSecItemDelete等は他Feature所有の資格情報まで対象にし得る。

**補完契約・実装案:** Featureと資格情報種類を含む安定キー、所有範囲を限定した検索/更新/削除、共有を明示する契約を提供する。

**残存制約・未確定点:** 一つの実行主体が許されたKeychain権限をFeatureごとのOS権限へ分割できるわけではない。access groupを増やすだけで相互アクセス禁止にはならない。署名変更時の継続も別検証。

**必要な検証:** A/Bが同じサービス・同じアカウント名を使い、A logoutがBを消さない。SideStore再署名後のアクセスも対象。

**現状判定:** 保存namespaceをKeychainまで広げた契約は現行台帳で未調査。  
根拠: S09, S01, R01

### D09 — URLSessionのcookie・認証・cache

**独立時の境界・主体:** 独立アプリは通常別の共有cookie/credential/cache環境を持つ。default/background URLSessionは共有credential storeを既定で使う。

**統合で失う差分:** URLSessionをFeatureごとに作るだけでは、共有ストレージまで自動分離されない。Aのlogin/logoutがBへ波及する可能性がある。

**補完契約・実装案:** Feature所有のsession設定と状態保存方針を決める。利用できる標準の分離機構を使い、永続性が必要なcookie/資格情報は所有者別に扱う。

**残存制約・未確定点:** ephemeralへの一律変更は永続loginを失うため同等の補完ではない。任意のHTTPCookieStorageを簡単に新規生成できると仮定せず、具体API/永続化方式を実装時に確認する。

**必要な検証:** 同一domainへA/B別アカウントで接続し、A logout/全cache削除相当操作がBへ波及しない。再起動後の期待する永続性も確認。

**現状判定:** 未調査。単なるURLSession wrapperの有無でなく共有状態を評価する。  
根拠: S10, S11, R01

### D10 — WKWebViewの永続Webデータ

**独立時の境界・主体:** 別アプリの通常WebViewデータは別のアプリ文脈になる。共有ブラウザでのSSOとは区別する。

**統合で失う差分:** 同じdefault website data storeを使うFeatureはcookie等が混ざり得る。

**補完契約・実装案:** WKWebsiteDataStore.init(forIdentifier:)による識別子付きデータストアをFeatureに割り当てる案がある。明示的共有と分離を選べるようにする。

**残存制約・未確定点:** Featureを消した時のWebデータ削除、UUIDの継続、並行操作は実機検証が必要。非永続モードだけに制限しない。

**必要な検証:** 同じサイトへ二つのアカウントでlogin、終了/復帰、片方のデータ消去で他方が維持されること。

**現状判定:** 標準APIを再利用して補完できる候補。JibunKit側の割当・寿命契約は未対応。  
根拠: S12, R01

### D11 — Web認証セッションと返却先

**独立時の境界・主体:** ASWebAuthenticationSessionは、その認証sessionを開始したアプリへcompletionを返す仕組みを持つ。ブラウザSSOの共有は独立アプリ同士でもあり得る。

**統合で失う差分:** Featureの認証要求・提示scene・取消・結果受信者を紐付けなければ、ホスト内で相手を取り違える。

**補完契約・実装案:** APIのsession/completionをそのまま所有者に保持させ、ホストは提示先や競合/取消を接続する。全認証を無理に共通openURL routerへ流さない。

**残存制約・未確定点:** OSの同時提示制約や外部認証providerのclient設定は別条件。SSOを全部禁止することも永続性を全部捨てることも補完の既定にしない。

**必要な検証:** A認証中にB要求、A取消/終了後のcompletion、正しいsceneと要求元だけへの返却。

**現状判定:** 一般認証は未調査。既存の標準的なsession境界を壊さず使う対象。  
根拠: S13, S14, R01

### D12 — URL・Universal Link・外部ファイル受信

**独立時の境界・主体:** 独立アプリでは登録URL/associated domain/document受信がそれぞれのアプリへ配送される。独立時にもURLの真正性確認は必要。

**統合で失う差分:** ホストの入口に集約され、どのFeature/scene/要求が所有するかが曖昧になる。file URLのアクセス権と寿命も受け渡す必要がある。

**補完契約・実装案:** ルート/受信種類/要求との対応を登録し、曖昧な重複を拒否する。security-scoped URLは処理完了まで必要なaccessを保持し、所有者ごとに解放する。

**残存制約・未確定点:** 既存アプリのbundleIDに固定されたassociated domain等はホスト側設定が必要。認証のnonce検証等、元から必要なFeatureの検証を省略しない。

**必要な検証:** cold/warm両起動、重複ルート、Feature終了後のcallback、二つの同時import、アクセス解放後の失敗を確認。

**現状判定:** 固定jibunkit URLと詳細routingは実装。一般callback/ファイル受信登録は未対応。  
根拠: R06, R09, S15, S40, R01

### D13 — 通知カテゴリ・action・foreground・取消

**独立時の境界・主体:** 通知の登録集合とdelegateはアプリ単位。setNotificationCategoriesは集合全体を置換する。

**統合で失う差分:** A/Bが各自正しい登録処理を行っても後から登録した方が前者を消し得る。全削除、badge、foreground提示の扱いにも同じ問題がある。

**補完契約・実装案:** カテゴリの和集合とID衝突検査、actionIdentifier/文字入力/消去actionの所有者配送、所有者限定取消、Featureの提示状態を考慮するforeground方針を実装する。

**残存制約・未確定点:** OSのアプリ別通知許可をFeatureごとに複製はできない。内部のFeature別通知設定は補助でありOS側の完全分離ではない。

**必要な検証:** 二つのcategory登録、同名ローカルID、返信action、Aだけ全取消、A表示中のB通知。

**現状判定:** 通知request IDとpayload routingは実装済み。現在のdelegateはactionIdentifierを分岐せず、foregroundも固定表示。一般契約は未対応。  
根拠: R07, R08, S16, S36

### D14 — APNs・remote pushの配送とサーバー識別

**独立時の境界・主体:** APNs device tokenはアプリと端末の組合せを識別する。

**統合で失う差分:** Featureを複数にしても独立アプリ数分のAPNs identityは得られない。payloadやtokenの管理をホストへ統合する必要がある。

**補完契約・実装案:** push種別/所有者の明示、token更新イベントの受渡し、Featureに必要な受信処理と通知extensionの構成を定義する。サーバー側のnamespaceも合意する。

**残存制約・未確定点:** 必要な署名capabilityが同じ利用条件で得られるか別確認。元の独立AppIDのtokenをそのまま流用する問題は無修正移植として前提にしない。

**必要な検証:** 適切な署名環境でA/B宛payloadとcold launch、token更新、A解除後の古いpushを検証。

**現状判定:** 未調査。必要契約と署名可否を分け、SideStore全般で不可と一括推定しない。  
根拠: S17, S01, R01

### D15 — BackgroundTasksの起動登録・期限・completion

**独立時の境界・主体:** BGTaskSchedulerのlaunch handlerは適切な起動時点で登録し、同じidentifierの重複登録を避ける必要がある。実行機会はOSが判断する。

**統合で失う差分:** Featureの画面を開いて初めて登録する設計では背景起動に間に合わない。取消/期限切れ/completionの所有者も共通ホストで混ざる。

**補完契約・実装案:** 起動時に要求を集約して登録し、必要Featureの処理環境を画面なしで復元する。OS taskとowner/requestを紐付け、完了/期限切れを一度だけ処理する。

**残存制約・未確定点:** 登録できることはOSが指定時刻に実行する保証ではない。独立アプリと同じ条件でも存在する不確定性と統合による損失を区別する。

**必要な検証:** 画面未表示のcold launch、二つのID、片方だけの期限切れ/取消/二重completionの抑止。

**現状判定:** 未対応。現在のhost phase配送とは別機構。  
根拠: S18, R05, R01

### D16 — Background URLSessionの再接続

**独立時の境界・主体:** background transferはアプリの通常画面の寿命とは別に進み、アプリ再起動時には対応sessionを復元してイベントを受ける。

**統合で失う差分:** 二つのFeatureが同じsession IDを使う、host callbackを一方が奪う、終了したFeatureの処理を別Featureへ誤配送する問題が生じる。

**補完契約・実装案:** 永続的なowner-session対応、ID払い出し、画面なしでのsession再生成、host completionの所有管理を設ける。

**残存制約・未確定点:** 既存OS制限やユーザーによるホスト停止の効果は内部Taskの再開で迂回できない。正確な再起動条件は対象APIごとに実機確認。

**必要な検証:** A/B転送を開始、ホスト再起動後にそれぞれ再接続、Aだけ取消しBが継続。

**現状判定:** 未対応。通常Task所有権だけではカバーしない。  
根拠: S19, R01

### D17 — ユーザー起点の継続処理・進捗・取消

**独立時の境界・主体:** iOS 26にはユーザー起点の作業を背景へ継続し、進捗や取消を扱うBGContinuedProcessingTaskがある。

**統合で失う差分:** 「background対応」を従来のrefresh/processing登録だけで済ませると、長時間の書出し等を持つFeatureの能力を落とし得る。

**補完契約・実装案:** 継続処理の要求を所有Featureに紐付け、システム進捗・取消をその要求へ接続する。機能本体の処理はFeatureが持つ。

**残存制約・未確定点:** 同時受付・実行資源・利用可能機能の条件は対象OS/端末で検証。一般的な無期限の背景実行許可ではない。

**必要な検証:** A継続作業中にBへ移動、ホスト背景化、AだけシステムUIから取消、Bの要求はそのまま。

**現状判定:** 初期棚卸しのbackground領域へ追加すべきAPI種別。未対応。  
根拠: S20, R01

### D18 — Spotlight・NSUserActivityと項目削除

**独立時の境界・主体:** CSSearchableItem.uniqueIdentifierはアプリ内で一意。domainIdentifierで項目群を管理でき、結果を開くとアプリ側へactivityが来る。

**統合で失う差分:** 二つのFeatureが同じ項目IDを使うと上書きし得る。全index削除が他Featureを巻き込み、結果の遷移先も共通入口になる。

**補完契約・実装案:** Feature別のdomain/item namespace、所有者限定の更新/削除、activityからFeature/sceneへのroutingを定める。

**残存制約・未確定点:** OSから見える提供アプリ名等はホストidentityのまま。表示内容にFeature名を含めても独立AppIDとは異なる。

**必要な検証:** A/B同じローカルitemID、Aだけ索引削除、cold起動でBの結果を正しい詳細へ開く。

**現状判定:** 初期棚卸しに明示されていない差分。未対応。  
根拠: S38, S39, R06

### D19 — 権限・プライバシー同意の単位

**独立時の境界・主体:** 保護対象資源へのOS許可はアプリの文脈で要求する。独立アプリ同士の同意状態はそれぞれ異なり得る。

**統合で失う差分:** ホストで一度許可された資源へ、別Featureが技術的にはアクセスできる。新Feature追加だけで以前の許可を意図せず継承する問題になる。

**補完契約・実装案:** OS許可とは別にFeatureの必要性とユーザー同意を管理し、要求元を説明する。協調するFeatureには許可された所有者だけに利用ハンドルを渡す。

**残存制約・未確定点:** 内部同意は同一プロセスに別のOS強制境界を作らない。OS設定の許可/取消はホスト全体へ作用する。機能ごとのAPIの権限粒度も個別調査する。

**必要な検証:** A許可/B内部拒否、OS全体拒否、後から新Feature追加、設定変更から戻った時の状態反映。

**現状判定:** 権限要求/拒否の一部例はあるが一般的なFeature別同意は未対応。  
根拠: S36, S01, R01

### D20 — 署名capability・Info.plist・構成の合成

**独立時の境界・主体:** 独立アプリはそれぞれのtarget設定・usage description・capabilityを持つ。

**統合で失う差分:** ホストの設定へ集約すると不足、上書き、両立不能な設定が発生する。実行時APIの登録だけでビルド時宣言は増えない。

**補完契約・実装案:** Feature要求から対象targetへ設定を接続する。集合の合成、Booleanの方針、排他的設定の拒否を区別し、Tuistの定義/補助関数で所有者付き診断を出す。

**残存制約・未確定点:** 要求しても署名profileで認められないentitlementは付与できない。各capabilityについてOS/API availability、profile、SideStore再署名を別軸で確認する。

**必要な検証:** 二つのFeature要求が合成されること、不足/競合が説明されること、署名後に実際に利用できること。

**現状判定:** 現状Project.swift中心の手動設定。汎用的な要求合成は未対応。  
根拠: R03, S01, S36

### D21 — AudioSessionの構成と中断・復帰

**独立時の境界・主体:** 独立アプリ同士でもiOSは要求を混合・中断等で調停する。全要求が同時成立する保証はない。アプリのaudio sessionは共有singleton。

**統合で失う差分:** 同一ホストのA/Bが直接setCategory等を呼ぶと、相手の構成を上書きする。外部OS中断と内部Feature間競合も別に管理する必要がある。

**補完契約・実装案:** 音声用途/構成要求/取得と解放を所有者単位にし、両立可能な組合せは成立させ、両立しない場合は理由を伴う中断/待機/拒否を返す。実際のplayer/recorder停止も協調契約に含める。

**残存制約・未確定点:** API内部の非公開OSスケジューリングを完全複製するのではなく、独立時の観測可能な能力を落とさない契約を定める。恣意的な全排他を補完完了にしない。

**必要な検証:** A再生/B録音、mix可能な二つ、OS中断、片方解放、ユーザーが停止した処理の誤再開がないこと。

**現状判定:** 未対応。単なるcategory setterのwrapperでは不足。  
根拠: S21, R01

### D22 — Now Playing・remote commands・再生対象

**独立時の境界・主体:** システムの再生UIには対象となる再生sessionがある。MPNowPlayingSessionは同一アプリで複数sessionを扱う標準機構を提供する。

**統合で失う差分:** 一つのグローバルmetadata/command handlerを無計画に共有すると、表示と操作対象が別Featureになる。

**補完契約・実装案:** 可能な部分はMPNowPlayingSessionを利用し、active対象・コマンドの所有者・終了後の切替を定義する。音声資源調停はD21と連携するが同一問題と扱わない。

**残存制約・未確定点:** システムが同時に独立した全Featureの再生UIを常時表示する保証はない。利用playerの種類による制約は別検証。

**必要な検証:** A/B同時再生session、操作対象切替、A終了後にBへ意図した切替、コマンドの誤配送ゼロ。

**現状判定:** 未対応。標準API再利用で独自実装を減らせる。  
根拠: S22, R01

### D23 — カメラ・AR等のcapture資源

**独立時の境界・主体:** 独立アプリでもカメラの利用には端末・同時利用・背景状態等の制限がある。AVCaptureMultiCamSessionのような複数入力を扱う標準機構もある。

**統合で失う差分:** Aを画面から外してBへ移ってもホストはforegroundであり得るため、Aのcaptureが意図せず残る。同じデバイスを複数sessionが奪い合う可能性もある。

**補完契約・実装案:** captureの所有権、可視性に応じた継続方針、取得/解放、競合の返し方を設計する。標準の複数入力機構が適合する場合は再利用する。

**残存制約・未確定点:** 全端末で全カメラ同時使用は要求しない。ARKitとの同時利用、system pressure、helper内利用は実機で別評価。

**必要な検証:** A preview→B capture、Aだけ停止、対応端末で両立可能構成、割込み/復帰とインジケーターの整合。

**現状判定:** 未調査。カメラ機能全体を除外する根拠にはならない。  
根拠: S26, S36, R01

### D24 — Bluetooth managerの復元と接続所有者

**独立時の境界・主体:** Core Bluetoothはmanagerの状態保存・復元を識別子で扱う。すべてのdelegateがアプリに一つというわけではない。

**統合で失う差分:** 復元IDやbackground起動の所有者が混ざると、誤ったFeatureへ接続状態を戻す。A停止時にBのscan/接続まで止める実装も問題。

**補完契約・実装案:** 既存managerのinstance境界を維持し、restore IDと起動経路を所有者へ紐付ける。必要な場合だけ同じphysical deviceの利用を調停する。

**残存制約・未確定点:** OSの背景scan/再起動条件は独立アプリでも制約される。Bluetooth全体を必ず一つの自作managerへ集約することは要件ではない。

**必要な検証:** A/B別manager・同じローカル復元名、ホスト再起動、A停止後のB接続継続。

**現状判定:** 未調査。台帳への具体的な復元ID/所有者項目の追加が必要。  
根拠: S24, S25, R01

### D25 — 位置情報・監視条件とアプリ単位の枠

**独立時の境界・主体:** 少なくともCLLocationManagerのregion monitoringにはアプリごとの20領域上限が文書化されている。デバイス全体にも資源制約がある。

**統合で失う差分:** 同じAPIをA/Bそれぞれで使う際、独立時の各アプリ枠が単一hostの枠へまとまる。ID衝突をなくしても上限は増えない。

**補完契約・実装案:** 要求者・監視状態・枠の使用を可視化し、共有できる同一条件の統合や優先順位を検討する。位置情報の取得/停止もowner単位にする。

**残存制約・未確定点:** 同API/同構成で上限を越える同時監視はnamespacingでは回復しない。監視対象の入替えは緩和であり全要求同時監視と同等ではない。CLMonitorや別方式の最新条件は別確認で、位置情報全体を20と一般化しない。

**必要な検証:** 各独立appでは上限内となる要求をhostで合成し、境界値/取消/再配分を比較する。背景時の実イベントも検証。

**現状判定:** 初期台帳で不足していた「枠の統合」差分。登録・調停は未対応、別方式での補完範囲は未調査。  
根拠: S23, S41, R01

### D26 — Widget・Control・既存extensionの組立て

**独立時の境界・主体:** 独立アプリは各自のextensionを持てる。WidgetBundleは一つのWidget extension内に複数Widgetをまとめられる。

**統合で失う差分:** 統合では種類/kind/保存先/更新対象を区別する必要がある。extensionをすべてhostに押し込むと本来あった別processやextension用途の境界を失う。

**補完契約・実装案:** 宣言とtargetへの接続を合成し、標準のWidgetBundleを使えるものはまとめる。種類が違うextensionや権限/lifetime上分離すべきものは対象別に保持する。

**残存制約・未確定点:** Widget一個追加ごとに新extensionが必須ではない。逆に全extensionを一つにまとめられるとも限らない。署名後の組込みと共有データのprocess間整合性が必要。

**必要な検証:** A/B Widgetが独立した値を表示し、Aの更新/削除がBへ波及しない。必要なら本体/extension同時writerも検証。

**現状判定:** Counter例と手動target定義あり。一般合成は未対応。追加手順の「別extension必須」と読める記述は修正候補。  
根拠: R03, R04, S27, S01

### D27 — App Intents・App Shortcuts・メタデータ

**独立時の境界・主体:** 独立アプリは各自のIntent/Entity/shortcut提供者を持つ。AppleはSwift Packages/static librariesでのApp Intents定義をサポートする方向を明示している。

**統合で失う差分:** hostへ全ソースを直置きする方式を必須にするとモジュール境界が悪化する。動的Registryに追加しただけでは静的メタデータに反映されるとは限らない。

**補完契約・実装案:** AppIntentsPackage等でFeatureの定義を組込み、型/Entity ID/依存注入/実行先を明確にする。コンパイル時の集約と実行時routingを分ける。

**残存制約・未確定点:** OSに見える提供アプリのidentityはhost。最新SDKでもローカライズやtarget間依存等の実ビルド検証が必要。

**必要な検証:** A/Bを別Packageに定義し、メタデータ抽出、実Shortcuts登録、画面なしの実行、Entity ID同名時の区別を確認。

**現状判定:** 現行はapp target内定義の経路。Package対応不可はOS制約ではない。一般化は未対応。  
根拠: R03, R04, S28, S29

### D28 — Live Activities・AlarmKit等のシステム継続表示

**独立時の境界・主体:** ActivityKitは個々のLive Activityの開始/更新/終了を扱い、AlarmKitはalarm IDとアプリのauthorizationを扱う。

**統合で失う差分:** 所有者を記録しない一覧/一括終了は他Featureの継続表示やalarmを巻き込む。Featureを閉じた後もOS側に残る状態がある。

**補完契約・実装案:** Featureとactivity/alarm IDの対応、所有者限定の更新/取消、cold launch再接続、Intentでの停止操作の配送を定める。

**残存制約・未確定点:** 許可や資源上限の単位はAPI別に調査する。実行/表示時間を独立時以上に保証しない。ここでは全数値上限の検証はしていない。

**必要な検証:** A/Bの継続表示とalarmを作成しAだけ終了/削除。OS UIからの操作を正しいFeatureへ返す。

**現状判定:** 初期棚卸しに明示されていない領域。未対応・個別条件未調査。  
根拠: S30, S31, R01

### D29 — 依存ライブラリ・runtime globals・resources

**独立時の境界・主体:** 独立アプリでは依存バージョン、ObjC runtime等、Bundle.mainのresource集合が別になる。SwiftPMの単一graphは共通依存の制約を満たす版を解決する。

**統合で失う差分:** 互換性のない依存版、ObjCクラス名やCシンボル、共通delegate/swizzling、画像/翻訳資源のhost依存が表面化する。Swiftの型名が同じだけなら、モジュールで区別される場合まで衝突と扱わない。

**補完契約・実装案:** 依存グラフはSwiftPM/Tuistへ任せる。resourceはBundle.module等を使う。SDKごとのinstance化可否やhost hookを整理し、衝突を所有Feature付きで説明する。

**残存制約・未確定点:** 任意の互換性のないSDKを同processで共存できるとは断定しない。名前変更、adapter、helperでの別graph等の代替はSDKと署名条件ごとに評価する。

**必要な検証:** 同名resourceのA/B表示、異なるSDK設定、衝突する依存要求が黙って片方を選ばず説明されること。

**現状判定:** Package/Tuist経路は整備。幅広いSDK衝突とruntime設定の共存は未調査。  
根拠: R02, R03, S08, S32

### D30 — 外部サービスidentity・CloudKit・データ出所

**独立時の境界・主体:** サービスはAppID、許されたcontainer、書込み元アプリ等を識別に使う。CKContainerは許可されたidentifierを選択でき、HKSource.bundleIdentifierは書込み元アプリを表す。

**統合で失う差分:** 単なるFeatureIDでは、署名されたAppIDやHealthKitの独立アプリ由来表示にはならない。逆にCloudKitは許可された別containerを維持できる場合がある。

**補完契約・実装案:** 外部identityをFeature内部の業務IDと分離して設計し、host/provider登録・container選択・内部の出所metadataを接続する。全データを一つへ強制統合しない。

**残存制約・未確定点:** 一つのhostを内部キーだけで複数の署名済みアプリに見せることはできない。必要capabilityとproviderの設定変更可否は個別確認。App Attest/HealthKit/認証で同じ結論に一括しない。

**必要な検証:** A/B別containerやアカウント、同名レコード、書込み元表示と内部Feature表示の区別。署名条件変更時のprovider照合。

**現状判定:** 初期棚卸しでは不足していた外部identity/出所の項目。未調査。  
根拠: S33, S34, S35, S01

### D31 — 無効化・削除・更新・privacyの集約

**独立時の境界・主体:** 独立アプリは導入/更新/削除単位が別。各アプリでの業務データ移行や共有cloudデータの処理はアプリ固有。

**統合で失う差分:** Featureのコードを次buildから外しても、既存保存値、通知、背景登録、検索項目などが残る場合がある。共有hostでは更新/再署名/OSの利用設定の効果もまとまる。

**補完契約・実装案:** 「非表示」「無効」「データ保持で除去」「データ消去」を区別し、所有者台帳に基づく停止/登録解除/データ整理を行う。必要なprivacy申告も利用SDK/targetと対応させる。

**残存制約・未確定点:** 独立appのOS設定項目や独立update単位をそのまま再現するものではない。削除がすべてのcloud/Keychainデータを自動消去する、という誤った独立baselineも置かない。

**必要な検証:** Aを除いた更新でBが継続、Aの不要通知/索引を処理、保持したAデータへ再追加時に正しく戻る。

**現状判定:** 保存継続/選択復元は一部整備。一般的なFeature removal/登録後始末は未対応。  
根拠: R01, R04, S17, S38, S37

### D32 — 補完不要な局所処理の識別

**独立時の境界・主体:** 純粋な計算、独立instanceの状態、既に適切に所有者が分かれた標準APIのcompletionなどは、必ずしもアプリ分離に依存しない。デバイス全体の制約は独立時にもある。

**統合で失う差分:** 失う境界がない部分まで一律のbrokerを挟むと、むしろ本来のinstance分離を壊すことがある。

**補完契約・実装案:** 変更なしで使えると根拠を確認できた部分はそのまま使い、必要な環境依存だけintegrationから注入する。「同じSDKを使う」は共有singletonである証拠ではない。

**残存制約・未確定点:** 「何も実装しない」を根拠なしの免除にしない。具体的なinstance/global/authorization/IDの単位を確認して判断する。

**必要な検証:** 同じコードを別App shellとhostへ組込み、標準APIの返却先やローカル状態がもともと分かれることを確認。

**現状判定:** 差分ごとに補完不要を証明する分類。領域全体をまとめて補完不要とする判定は未実施。  
根拠: R01, S13, S24, S32

## 現行実装について特に区別すべきこと

`MiniAppLifecycleDispatcher`はhost全体のphaseを全handlerへ順序を保って届ける機構であり、これを作ったこと自体は妥当である。ただしFeature instanceの生成/終了やTaskの取消は担当していない。hostのactiveを各Featureの表示中と同じにしない。[R05, R09]

`AppNavigation.shared`は単一の`NavigationPath`を持ち、Featureを開く操作で置換する。ここから読み取れるのは「Feature/scene別の経路保持の一般機構はまだない」ということであり、すべての画面の状態が実機で必ず消失したという実測報告ではない。[R06]

`NotificationAppDelegate`は通知payloadのrouteを取り出して画面へ送るが、actionIdentifierや文字入力actionを所有Featureへ配送するコードはこのファイルにない。foreground表示も一律banner/list/soundである。入口を一つにしただけで通知全体の共存が完成するわけではない。[R07]

`MiniAppContext`の通知request IDにはFeature namespaceが含まれ、所有範囲照合もある。既存のこの成果は維持し、カテゴリ、action、取消、永続登録等へ必要な範囲を広げる。namespaceを権限検査の代用品にはしない。[R08]

## 実装に先立って揃える契約

### 安定identityと実行identityを分ける

FeatureIDは保存やOS登録に使う安定識別子、InstanceIDはsceneや再起動世代を含む実行単位、RequestIDは個別作業の識別子とする案が適する。API名をこの通りにする必要はない。どの契約も一つの巨大な汎用event busへ押し込む必要はない。

永続登録はFeatureIDへ結び、現在のUI応答はInstanceIDへ結ぶ。同じFeatureの別windowを別Featureと扱わず、閉じる前のcallbackを再生成後のinstanceへ自動転送しない。これはD01/D02/D04/D12/D16の共通前提になる。

### 取得/解放と結果を対にする

音声、capture、idle timer等は、所有者が取得した要求を所有者単位で解放する。戻り値には成立・待機・中断・拒否と理由を区別する。すべて拒否すれば衝突しない、という実装を共存完成とは扱わない。

### UIの閉鎖と処理終了を同一にしない

画面を離れたら止める処理、Feature sessionを終了すると止める処理、ユーザーが明示的に背景継続させた処理を分ける。音声再生や転送をFeature切替だけで止める設計は避ける一方、表示に依存するcapture等を知らないまま継続させない。

### 実行時とビルド時の合成を分ける

実行時には所有者・状態・callback・資源要求を接続する。ビルド時にはInfo.plist、entitlements、extension target、Intent metadata、resources、依存関係を接続する。Tuist/SwiftPMを利用し、独自の第二のプロジェクト生成基盤を増やすことを目的にしない。

## 推奨する着手順序（対象を削る優先順位ではない）

1. **helper経路の技術的成立性と、Feature/instance/scene/requestの寿命契約を並行して確かめる。** 後続全体の前提が変わり得るため。helperへの全面移行を先に決めない。
2. **現行の保存・通知・遷移・host phaseを所有者付き契約へつなぐ。** 既存の成果を捨てず、取消・解除・再開を追加する。
3. **共有入口と永続登録を処理する。** URL/ファイル/activity、通知category/action、background task、background URLSession、Spotlight等。
4. **共有資源と状態を補完する。** AudioSession/Now Playing、Web/認証状態、camera/位置/Bluetooth、global UI設定、DB復元時の調停。
5. **ビルド/extension/外部identity/枠と利用者操作を閉じる。** 設定合成、Intent/Widget、Feature除去、残存制約の説明。

各番号を巨大な一括変更にする必要はない。独立した契約の実装と検証を並行してよい。遅い項目を1.0範囲から外す意味ではない。

## 検証方針

検証fixtureは実用アプリ製品として育てない。同じFeature sourceを「別App shell二つ」と「JibunKitに二つ統合」の両形で動かし、同じOS・署名条件のbaselineと比較する。特に音声やOS背景動作は、独立版で保証されない挙動をhostだけの完成条件にしない。

状態/識別子の単体検証、iOS host/extensionでの統合検証、署名/権限/実資源の実機検証を使い分ける。対象と無関係な全経路を小変更ごとに反復することや、形式的な証拠収集を成果に数えることは推奨しない。

各contractで必要な基本パターンは、同名のローカルIDを持つ二者、同時要求、片方取消/失敗、片方終了後の遅延callback、他方継続、再開/cold launchである。資源の組合せは互いに独立な全APIの全直積ではなく、同じ共有境界を使う要求について実際に分かれる意味上のケースを選ぶ。

## 今回まだ技術判定を確定していない項目

- helper extensionのSideStore/Personal Teamでの起動・再署名・権限・対象OS最低版・lifetime。App Store/TestFlightの成功をそのまま代用しない。
- 通常URLSessionでの永続cookie/credentialをFeature別に保持する具体方式。別session生成だけでよいとしない。
- 最新CLMonitorを含む監視枠、各Live Activity/AlarmKit/background APIの現在の上限や受付条件。旧APIや別APIの数値を流用しない。
- ARKit/camera同時利用、Core Bluetooth復元、音声player種別の組合せと物理端末固有の条件。
- HealthKit、CallKit/PushKit、Network Extension/VPN、HomeKit、NFC等の特殊なcapabilityについて、同じ署名条件での利用可否と複数Feature共存。領域名だけで可/不可を確定しない。
- providerに依存する認証/attestation/cloud identityの設定可能範囲、複数の非instance化SDKや互換性のない依存版の解決可能性。

これらは対象外の宣言ではなく、残調査・最小技術検証として台帳に残す項目である。公開資料に記載のない挙動を、推測だけでOS制約または成功保証に分類していない。

## 1.0判定への反映

現在の5分類を維持する。補完済み・検証済み、補完不要（根拠あり）、技術的に補完不能（限定された性質・根拠・可能な緩和策あり）、未対応、未調査である。[R01]

「所有者を登録できる」「衝突を検出できる」は、回復可能な機能を回復したことと同じではない。反対に、OS app identityや同じAPIのapp枠を再現できないことを理由に、同領域のrouting・取消・状態分離を省略しない。

台帳はSDKや運用条件を明記して維持する。新しいAPIや新しい統合差分が判明したら更新する。全将来APIに対する形式的な網羅性の証明を完成要件に追加するのではなく、現行対象条件で必要な差分の実装と証拠を評価する。

## 出典

APIドキュメント、AppleによるWWDC説明、Apple Platform Security、Swift公式資料、Apple DTS回答、および対象コミットのリポジトリ資料。アーカイブ文書は該当APIの概念/契約に限って用い、現在の全APIや利用条件へ一般化しない。DTS回答では担当者の初期見解ではなく後続の検証結果まで確認した。


- **R01** — [JibunKit：共存の制約と1.0上位完成基準](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/docs/coexistence-boundaries.md)
- **R02** — [JibunKit：Package.swift](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Package.swift)
- **R03** — [JibunKit：Project.swift](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Project.swift)
- **R04** — [JibunKit：ミニアプリ追加・保存・画面・システム連携の契約](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/docs/mini-apps.md)
- **R05** — [JibunKit：MiniAppLifecycleDispatcher](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Sources/JibunKitCore/MiniAppHostPhase.swift)
- **R06** — [JibunKit：AppNavigation](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Sources/JibunKit/AppNavigation.swift)
- **R07** — [JibunKit：NotificationAppDelegate](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Sources/JibunKit/NotificationAppDelegate.swift)
- **R08** — [JibunKit：MiniAppID / MiniAppContext](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Sources/JibunKitCore/MiniAppID.swift)
- **R09** — [JibunKit：JibunKitApp](https://github.com/y-aplus/JibunKit/blob/1b6ad200eba67733d75c791efd258cf6e7ac0bfc/Sources/JibunKit/JibunKitApp.swift)
- **S01** — [Apple Platform Security：Security of runtime process](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web)
- **S02** — [Swift言語ガイド：Concurrency / cooperative cancellation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- **S03** — [Apple：Creating enhanced security helper extensions](https://developer.apple.com/documentation/xcode/creating-enhanced-security-helper-extensions)
- **S04** — [Apple DTS：Unable to upload an app with ExtensionFoundation（2025年11月の後続回答を参照）](https://developer.apple.com/forums/thread/803896)
- **S05** — [Apple：ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)
- **S06** — [Apple：UIAppearance containment](https://developer.apple.com/documentation/uikit/uiappearance/appearance(whencontainedininstancesof:))
- **S07** — [Apple：UIApplication.isIdleTimerDisabled](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled)
- **S08** — [Apple：Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)
- **S09** — [Apple：Sharing access to keychain items among a collection of apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
- **S10** — [Apple：URLSessionConfiguration.urlCredentialStorage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/urlcredentialstorage)
- **S11** — [Apple：URLSessionConfiguration.httpCookieStorage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage)
- **S12** — [Apple：WKWebsiteDataStore.init(forIdentifier:)](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init(foridentifier:))
- **S13** — [Apple：ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- **S14** — [Apple：ASWebAuthenticationSession.prefersEphemeralWebBrowserSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession)
- **S15** — [Apple：UIDocumentPickerViewController](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)
- **S16** — [Apple：UNUserNotificationCenter.setNotificationCategories(_:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setnotificationcategories(_:))
- **S17** — [Apple：Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
- **S18** — [Apple：BGTaskScheduler.register(forTaskWithIdentifier:using:launchHandler:)](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:))
- **S19** — [Apple：Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- **S20** — [Apple WWDC25：Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/)
- **S21** — [Apple：Audio Session Programming Guide / Introduction（アーカイブ）](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/Introduction/Introduction.html)
- **S22** — [Apple WWDC22：Explore media metadata publishing and playback interactions](https://developer.apple.com/videos/play/wwdc2022/110338/)
- **S23** — [Apple：CLLocationManager.startMonitoring(for:)](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:))
- **S24** — [Apple：Core Bluetooth background processing（アーカイブ）](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- **S25** — [Apple：TN3115 Bluetooth state restoration app relaunch rules](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules)
- **S26** — [Apple：AVCaptureMultiCamSession](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession)
- **S27** — [Apple：WidgetBundle](https://developer.apple.com/documentation/swiftui/widgetbundle)
- **S28** — [Apple WWDC25：Explore new advances in App Intents](https://developer.apple.com/videos/play/wwdc2025/275/)
- **S29** — [Apple WWDC25：Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244/)
- **S30** — [Apple：Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- **S31** — [Apple WWDC25：Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)
- **S32** — [Swift：Package Registry Service Specification / dependency resolution](https://docs.swift.org/latest/documentation/packagemanagerdocs/registryserverspecification/)
- **S33** — [Apple：CKContainer.init(identifier:)](https://developer.apple.com/documentation/cloudkit/ckcontainer/init(identifier:))
- **S34** — [Apple：HKSource.bundleIdentifier](https://developer.apple.com/documentation/healthkit/hksource/bundleidentifier)
- **S35** — [Apple WWDC26：Secure your apps with App Attest](https://developer.apple.com/videos/play/wwdc2026/201/)
- **S36** — [Apple：Requesting access to protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources)
- **S37** — [Apple：Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- **S38** — [Apple：CSSearchableItem](https://developer.apple.com/documentation/corespotlight/cssearchableitem)
- **S39** — [Apple：App Search Programming Guide / Index App Content（アーカイブ）](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppSearch/AppContent.html)
- **S40** — [Apple：Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- **S41** — [Apple：Region Monitoring and iBeacon（アーカイブ、API別の上限例）](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html)
- **S42** — [Apple：AppExtensionProcess](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess)
