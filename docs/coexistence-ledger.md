# JibunKit 統合差分台帳

更新日: 2026-09-10
目的: 独立iOSアプリをJibunKitのFeatureとして単一hostへ統合したときに失われる境界の**現在状態**を追跡する正本。

## 文書の役割

- **上位完成基準・判定規則**: [`coexistence-boundaries.md`](coexistence-boundaries.md)
- **現在状態の正本**: このファイル。D01以降のIDは原則として再利用・振り直ししない。
- **固定調査記録**: [`research/2026-09-09-integration-boundary-research.md`](research/2026-09-09-integration-boundary-research.md)。2026-09-09にChatGPT上のAIが`main` `1b6ad200...`を対象に作成した根拠付き調査スナップショット。baseline、統合差分、補完案、残存制約、検証条件、出典URLの詳細はそちらを正本とする。

歴史的な調査内容は固定調査記録、現在の実装状態・判定はこの台帳を優先する。新しい事実で過去の調査が誤っていた場合は、調査記録を消去せず訂正を追記し、この台帳を更新する。

## 状態の定義

- `補完済み・検証済み`: 必要な補完と比較検証が完了。
- `補完不要`: 独立時の境界が統合後も維持される根拠があり、追加補完が不要。
- `技術的に補完不能`: 限定された失われる性質について、根拠・影響・可能な緩和策を確認済み。
- `未対応`: 差分と補完方向は特定できているが、必要な実装または検証が残る。
- `未調査`: baseline、統合差分、補完可能性のいずれかに重要な未確認が残る。

部分実装があってもD項目全体の合格条件を満たすまでは`未対応`等のままとし、部分成果を`現在状態`へ記録する。

## 台帳

| ID | 対象 | 状態 | 現在状態 |
| --- | --- | --- | --- |
| D01 | ホスト活動状態・scene・Feature表示状態 | 未対応 | host集約phase配送は補完・CI検証済み。34491955629でscene接続UUID・phase・Feature選択を区別するDefinition callbackを検証。未生成Featureへの配送、非選択の処理継続、OS背景化/復帰のiOS試験35.264秒、二dispatcherの片方だけの終了・再接続世代・再入順の4unitが成功。[接続ガイド](guides/scene-feature-activity.md)。OS上の複数window運用、Feature実行instanceの明示生成/終了・Runtime接続、任意Viewの可視/提示状態は残る。 |
| D02 | タスク・購読・要求の所有権と取消 | 未対応 | MiniAppTaskScopeでowner別Task取消、実行中の片方だけの取消、他owner継続、owner解放をunitで確認済み。CI隔離hostでの二Featureの起動・片方の取消・他方継続/正常完了は[34320179116](https://github.com/y-aplus/JibunKit/actions/runs/34320179116)で成功。呼出時点のTask群を取消して全完了を待つcancelAllAndWaitは[34323337796](https://github.com/y-aplus/JibunKit/actions/runs/34323337796)でunit/build成功。別batch維持とcleanup完了待ちも[34323800250](https://github.com/y-aplus/JibunKit/actions/runs/34323800250)で成功。MiniAppRuntimeで新規受付閉鎖・Task完了待ち・資源の逆順後始末を追加し、idle leaseとの接続は34371355575のunit・iOS該当テストで成功（run全体はWeb保持失敗）。終了待ち途中の受付拒否・Task cleanup完了待ち・owner解放時の順序は34377803005でunit成功。同期/非同期の終了hookと共有復元経路の接続は提供済み。非同期解放待ち・復元前の解放順序は34430649082でunit成功。34439496158でURLSessionのgraceful終了・delegate追加解放後の保存、Runtimeの要求取消後のlogoutと他session維持が実HTTPで成功。Foundation NotificationCenterのowner別購読・個別取消・queued MainActor配送抑止・Runtime終了接続を追加。34484781329で実NotificationCenterの9テスト（0.734秒）、取消済みtokenの反復解放とdeinitから取消への再入、共有123テスト、iOS build/IPAが成功。並行threadからの個別取消は受理済み配送が残り得ることを区別する。[購読接続ガイド](guides/owned-notification-observations.md)。各Featureのその他の購読・要求・DB接続を寿命へ登録する作業、および非協調処理の扱いは残る。[接続ガイド](runtime-restore-integration.md)。 |
| D03 | クラッシュ・ハング・メモリとhelper extension | 未対応 | 協調的緩和は未対応。helperによる追加補完可能性は今回新たに発見した実装判断用の検証課題。 |
| D04 | 画面遷移・復帰・提示と複数scene | 未対応 | AppNavigationのsingletonを外し、WindowGroup内のviewがwindowごとの状態を所有する構造へ変更。process通知はMiniAppSceneRouterが活動中/直近sceneへ一件配送し、scene指定URLは当該scene内で処理する。34440565104で起動前保留・活動遷移/解除・再入のunit、二navigation実体のiOS試験（52.260秒）、実通知遷移回帰（68.971秒）が成功。34484074366でFeature別の値ベース経路保持と下部切替メニュー、一覧再開・個別reset・OS経由root URL・他Featureの経路保持をiOSで検証（79.425秒）。View内部状態、OS上の複数window運用・提示調停・UIViewController接続は残る。[現在の契約](scene-navigation.md)。 |
| D05 | 画面外観・idle timer等のアプリ共有設定 | 未対応 | idle timerのFeature/操作別leaseを追加。他owner継続・同一owner複数要求・冪等release・解放時後始末のunitとiOS buildは[34366651143](https://github.com/y-aplus/JibunKit/actions/runs/34366651143)で成功。iOS共有設定の二Feature取得・片方解除・最終解除は[34367286197](https://github.com/y-aplus/JibunKit/actions/runs/34367286197)で成功（49.277秒）。Runtime終了時の自動解除接続は34371355575で成功（44.083秒）。34497999557でscene選択/活動に従う任意scopeの解除/復帰、他owner保持、Runtime閉鎖をiOSで検証（72.461秒）。複数scene/foreignイベント/再入の4unitも成功。[接続ガイド](guides/scene-idle-timer.md)。実機の実際の自動ロックと外観設定全般は残る。 |
| D06 | UserDefaults・通常ファイル・DB配置 | 未対応 | MiniAppContextのUserDefaults namespaceとMiniAppFilesは実装・限定検証済み。DB、Keychain、Web/ネットワーク状態までの一般契約は別D項目を含め未完。 |
| D07 | 復元・移行・リセット中の処理停止 | 未対応 | 選択復元のstop/apply/resumeをDefinition経由でhostへ接続。製品BackupScreenで成功経路と停止・部分適用・再開・両失敗の4経路、他ownerのTask/データ維持を確認（34389357592）。プロセス共通の復元予約で重複planを変更前に拒否し、非重複は並行実行。予約解除と取消開始境界は34412140159でunit成功。複数owner途中取消の未着手保護、snapshot exportとの調停もunitで確認。実機JSON書出し・読込み・選択復元もユーザー確認済み。非同期資源解放待ちと復元の結合は34430649082でunit成功。34502469319で停止途中の失敗回復、回復失敗の理由保持と画面区別、回復中の予約保持と他owner継続、native SQLite BUSY close後の新Runtime受付を検証。既存を含む実画面6失敗経路は248.781秒で成功。[回復の契約と証拠](verification/2026-09-11-restore-stop-recovery.md)。34506390553でwithStoreAccessの通常アクセス重複、復元/snapshotとの相互拒否、取消後の全件終了待ち、native SQLite transaction、共有画面の使用中拒否/完了後の復元/他owner継続を検証（UI61.558秒）。[通常操作の接続](guides/store-access-coordination.md)。実FeatureのDB接続・通常操作入口への登録・別processとの排他、移行/リセットへの適用は残る。[検証記録](verification/2026-09-10-runtime-lifetime.md)。 |
| D08 | Keychainと資格情報の削除範囲 | 未対応 | generic passwordのFeature/service別namespace、取得・更新・account削除・service内全削除を追加。native Keychainで同名accountのA/B分離と他service保持は[34337653973](https://github.com/y-aplus/JibunKit/actions/runs/34337653973)で成功（macOS、0.230秒）。iOS隔離hostで保存・再起動・A logout後のB保持は[34338195098](https://github.com/y-aplus/JibunKit/actions/runs/34338195098)の該当テストで成功（63.720秒、run全体は通知action回帰失敗）。iOS保持/logout再検証も34342836098で成功。native accessibilityの明示指定・変更・省略時保持は[34345684119](https://github.com/y-aplus/JibunKit/actions/runs/34345684119)でiOS属性読戻し成功。生体認証/アクセス制御・同期・署名変更後の継続は残る。 |
| D09 | URLSessionのcookie・認証・cache | 未調査 | defaultの共有Cookieとephemeralの非永続ストアをApple仕様で確認。同一server identityのCookie/credential/cacheと片方削除はunit成功。Feature/profile別native disk cacheを提供。34431912303で実HTTPのCookie送信・cache-only利用・片方削除後の他owner維持が成功。認証challenge/redirect/logoutも34432354335で成功。Keychain経由の永続Cookie明示save/reload/clearを追加し、期限・破損・HTTP再生成/logoutは34432845944で成功。34433288351でiOS process再起動・Secure/HttpOnly保持・片方logout後の他Feature保持が成功。34435476250で同Featureの複数profileのHTTP再生成/logout・archive異常時の保持・iOS回帰も成功。34437448875でパスワード資格情報のFeature/profile別明示保存・native認証先/既定user保持・実HTTP認証/logout・iOS再起動が成功。34439496158でMiniAppURLSessionLifetimeとRuntimeを接続した遅延HTTP/取消/logout試験も成功。自動保存・非パスワード資格情報・backgroundとの比較は残り、一律ephemeral化は行わない。[接続ガイド](network-integration.md)。[検証計画](verification/2026-09-10-network-isolation.md)。 |
| D10 | WKWebViewの永続Webデータ | 未対応 | Feature/profile別の安定UUIDと標準の永続WKWebsiteDataStore割当を追加。34348667212で保存後の再起動にCookie未検出。検証用WebViewへストアを割当・保持する形へ修正し[34351393142](https://github.com/y-aplus/JibunKit/actions/runs/34351393142)の該当テストで再起動保持・A全削除後のB保持が成功（65.811秒、run全体は通知操作失敗）。34359547457では再起動後Cookie欠落が再発。保存読戻しと通常background移行後の再起動を明示し[34362662224](https://github.com/y-aplus/JibunKit/actions/runs/34362662224)で成功（79.265秒）。34371355575ではCookie欠落が再発。ページnavigation完了を待って操作する検証へ修正し34373928804でCI全体成功。保存直後の強制終了耐性、IndexedDB等その他のWebデータ・Feature削除時の寿命調停は残る。  34385366877で識別子付き/標準ストアの両方の再起動保持、A削除後のB保持をログ確認。過去の不安定性は原因未確定。[比較診断](verification/2026-09-10-web-data-persistence.md)。34505014278で同一base URLのHTML/JavaScript経由のlocalStorage・Cookieを二ownerで保存し、通常background後の再起動保持、A削除直後の未検出、再起動後のB保持を検証（91.121秒）。HTTP取得・即時永続化・他Webデータ一般には拡大しない。[実ページの検証記録](verification/2026-09-11-web-storage-ownership.md)。 |
| D11 | Web認証セッションと返却先 | 未調査 | 一般認証は未調査。既存の標準的なsession境界を壊さず使う対象。 |
| D12 | URL・Universal Link・外部ファイル受信 | 未対応 | 固定jibunkit URLと通知詳細routingは実装済み。一般URL callback、Universal Link、外部ファイル受信・security-scoped URL所有は未対応。 |
| D13 | 通知カテゴリ・action・foreground・取消 | 未対応 | notification request ID namespaceとpayload routingは実装済み。actionIdentifier/文字入力/消去の所有者配送unitと従来open実通知回帰は[34324423834](https://github.com/y-aplus/JibunKit/actions/runs/34324423834)で成功。categoryの所有者namespace・合成・衝突拒否は[34325938194](https://github.com/y-aplus/JibunKit/actions/runs/34325938194)でunit/build成功。所有者限定のpending/delivered一括取消とRecords接続は[34326889563](https://github.com/y-aplus/JibunKit/actions/runs/34326889563)でunit・独立/統合build成功。Feature別foreground方針と既定値維持は[34327561372](https://github.com/y-aplus/JibunKit/actions/runs/34327561372)でunit/build成功。動的category更新の所有者別置換・失敗時保持は[34328104046](https://github.com/y-aplus/JibunKit/actions/runs/34328104046)でunit/build成功。CI隔離hostの二FeatureでOS登録読戻し・更新/解除・再起動再登録は[34328684533](https://github.com/y-aplus/JibunKit/actions/runs/34328684533)で成功（39.750秒）、従来通知tap回帰も成功。foreground実通知の所有者別callback配送は[34331529826](https://github.com/y-aplus/JibunKit/actions/runs/34331529826)で成功（34.900秒）。独自actionのOS操作・所有者配送・他Feature表示維持は[34334411845](https://github.com/y-aplus/JibunKit/actions/runs/34334411845)で成功（39.602秒）。34338195098ではaction通知カード未検出で回帰失敗。画面遷移競合を避ける検証用表示方針・背景移行確認後、34340335666では通知カードを検出したがGrouped状態のままactionボタン未検出。先行foregroundテストの通知をowner限定で後始末し[34342836098](https://github.com/y-aplus/JibunKit/actions/runs/34342836098)でaction回帰成功（38.000秒）。34348667212で再びactionボタン未検出。34351393142でも通知コンテナ長押しでは未展開。取得した前後スクリーンショットで画面下部のstack表示を確認し、上スワイプ後も34354020916でaction未展開。予約前のnative category/action読戻しを必須にし、34356757243ではnative category/action読戻し成功、座標長押しでもaction未展開。本文付き通知と左スワイプのView経路で[34359547457](https://github.com/y-aplus/JibunKit/actions/runs/34359547457)のactionテスト成功（86.228秒）。foreground表示結果の共存検証は未完。 |
| D14 | APNs・remote pushの配送とサーバー識別 | 未調査 | 未調査。必要契約と署名可否を分け、SideStore全般で不可と一括推定しない。 |
| D15 | BackgroundTasksの起動登録・期限・completion | 未対応 | 未対応。現在のhost phase配送とは別機構。 |
| D16 | Background URLSessionの再接続 | 未対応 | 未対応。通常Task所有権だけではカバーしない。 |
| D17 | ユーザー起点の継続処理・進捗・取消 | 未対応 | 初期棚卸しのbackground領域へ追加すべきAPI種別。未対応。 |
| D18 | Spotlight・NSUserActivityと項目削除 | 未対応 | MiniAppSpotlightNamespaceでnative属性を保持したFeature別item/domainと限定削除を追加。34509301964の署名付きiOS hostで同じlocal IDのA/Bを実indexから読戻し、A削除後のB identifier/domain/title保持を検証（52.529秒）。属性copyの参照分離もunit確認。textContentのquery返却、検索結果起点のNSUserActivity/host/scene/cold launch配送は未完。[検証記録](verification/2026-09-10-spotlight-ownership.md)。 |
| D19 | 権限・プライバシー同意の単位 | 未対応 | 権限要求/拒否の一部例はあるが一般的なFeature別同意は未対応。 |
| D20 | 署名capability・Info.plist・構成の合成 | 未対応 | Feature別のplist/entitlements要求をTuist標準helperで合成。異値衝突、明示resolution、限定した文字列集合、target別分離を追加。34510497056でnative helper試験、生成probeのビルド済みInfo.plist/実ad-hoc署名、通常app/Widget/IPAとUI回帰が成功。[接続ガイド](guides/feature-build-requirements.md)。多言語用途説明、privacy manifest、構造化配列の一般合成、target/依存/Registryの一元化、実provisioningと再署名後の利用条件は残る。 |
| D21 | AudioSessionの構成と中断・復帰 | 未対応 | 未対応。単なるcategory setterのwrapperでは不足。 |
| D22 | Now Playing・remote commands・再生対象 | 未対応 | 未対応。標準API再利用で独自実装を減らせる。 |
| D23 | カメラ・AR等のcapture資源 | 未調査 | 未調査。カメラ機能全体を除外する根拠にはならない。 |
| D24 | Bluetooth managerの復元と接続所有者 | 未調査 | 未調査。台帳への具体的な復元ID/所有者項目の追加が必要。 |
| D25 | 位置情報・監視条件とアプリ単位の枠 | 未対応 | 初期台帳で不足していた「枠の統合」差分。登録・調停は未対応、別方式での補完範囲は未調査。 |
| D26 | Widget・Control・既存extensionの組立て | 未対応 | Counter例と手動target定義あり。一般合成は未対応。追加手順の「別extension必須」と読める記述は修正候補。 |
| D27 | App Intents・App Shortcuts・メタデータ | 未対応 | 現行はapp target内定義の経路。Package対応不可はOS制約ではない。一般化は未対応。 |
| D28 | Live Activities・AlarmKit等のシステム継続表示 | 未対応 | 初期棚卸しに明示されていない領域。未対応・個別条件未調査。 |
| D29 | 依存ライブラリ・runtime globals・resources | 未調査 | Package/Tuist経路は整備。幅広いSDK衝突とruntime設定の共存は未調査。 |
| D30 | 外部サービスidentity・CloudKit・データ出所 | 未調査 | 初期棚卸しでは不足していた外部identity/出所の項目。未調査。 |
| D31 | 無効化・削除・更新・privacyの集約 | 未対応 | 保存継続/選択復元は一部整備。一般的なFeature removal/登録後始末は未対応。 |
| D32 | 補完不要な局所処理の識別 | 未調査 | 差分ごとに補完不要を証明する分類。領域全体をまとめて補完不要とする判定は未実施。 |

## 更新規則

- 実装・検証が進んだら、該当D番号の`状態`と`現在状態`を更新し、Issue / commit / CI / 実機証拠へのリンクを必要に応じて追記する。
- 一つのD項目が大きすぎて独立した判定が必要になった場合は、既存IDの意味を変えず新しいD番号を追加する。
- 新しいAPIや新しい統合差分を発見した場合もD33以降を追加し、過去の番号を振り直さない。
- `補完不能`は領域全体ではなく、限定した失われる性質について根拠付きで用いる。残りのrouting・取消・状態分離等を自動的に免除しない。
- `補完不要`は「実装していない」の言い換えにせず、独立時の境界が維持される根拠を固定調査記録または追加調査へ残す。

## 初期化時点の補足

- D01: host集約phase配送は複数Featureへの実イベントと再入時の順序までCI確認済みだが、Feature/scene/instance別の寿命は残る。
- D02: MiniAppTaskScopeによるowner別Task取消・他owner継続・owner解放はunit確認済み。台帳初期化時点ではCI隔離hostのFeature間UI検証結果待ち。
- D06: UserDefaults namespaceとMiniAppFilesは実装・限定検証済み。[native SQLite比較](verification/2026-09-11-sqlite-isolation.md)で同名WAL DB、片側削除/再接続、Backup APIによる片側復元と他owner保持をmacOSで確認。別process writer・iOS Data Protection・他DBまでの完了ではない。復元の協調や他の状態分離はD07–D11等で別管理する。
- D12/D13: URL/通知routingとnotification request namespaceの既存成果は維持する。一般callback、通知category/action等は未完として扱う。

## 「未調査」で残っている具体的な確認

基礎文献の棚卸しは固定調査記録にある。「未調査」は文献を一から読む指示でも、すべて実験だけが残るという意味でもない。下表は未確認の内容と次の確認作業を分ける。調査完了や補完不能を先に判定したものではない。

- **仕様確認**: 対象API・署名・OS条件の根拠を追加確認する。
- **比較実験**: 独立アプリ相当と統合後の挙動を、実機/Simulator/適切なホスト試験で比較する。
- **設計検証**: 補完方式を組み込み、競合・取消・復帰まで成立するか試す。

| ID | 残る確認の種類 | 次に確認する具体的な内容 |
| --- | --- | --- |
| D09 | 仕様確認・比較実験・設計検証 | Cookie全属性/永続化時点、非パスワード資格情報、backgroundへの再接続条件。公開APIの保持条件と二ownerの実通信を比較する。 |
| D11 | 仕様確認・比較実験 | ASWebAuthenticationSessionの同時開始・提示先・callback/cancel配送を二Featureで比較し、標準session境界が保つ範囲とhost調停が必要な範囲を確定する。 |
| D14 | 仕様確認・比較実験 | 対象署名でAPNs entitlementを使える条件、app単位tokenを複数Featureのサーバー識別へ接続する条件を確認。可否を一括推定せず、登録/配送の実証可能な条件を記録する。 |
| D23 | 仕様確認・比較実験・設計検証 | カメラ/ARの同時利用・中断/復帰・資源解放を独立時と比較し、Feature所有者間の取得/競合/返却方式を検証する。 |
| D24 | 仕様確認・比較実験 | Bluetooth restoration identifierの重複・再起動時のmanager復元・callback所有者を確認。実機と周辺機器が必要な試験を切り分ける。 |
| D29 | 比較実験・設計検証 | 同一SDKの異なる設定/依存version、process-global delegate/resourcesについて具体的な二Feature構成を作り、衝突と接続・診断手順を検証する。 |
| D30 | 仕様確認・比較実験・設計検証 | CloudKit等のcontainer/account/record所有権と署名条件を確認。同じ外部identityを使う二Featureの読書き・削除・復帰で差分を検証する。 |
| D32 | 仕様確認・比較実験 | 局所的な計算・値変換等は、global状態・登録・外部資源を持たない条件を確認して個別に補完不要を判定する。領域全体を一括免除しない。 |

`未対応`の項目にも未確認部分は残る。たとえばD03のhelper extensionの補完範囲、D04のOS上の複数window、D25の監視枠と代替方式は個別の比較実験・設計検証が必要。実装順にこの具体欄と各領域のガイドを更新し、完了した実験を未調査のまま放置しない。
