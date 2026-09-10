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
| D01 | ホスト活動状態・scene・Feature表示状態 | 未対応 | host集約phase配送は補完・CI検証済み。未表示の二Featureへの実イベント配送、再入時の順序一致まで確認済み。Feature/scene/instance別の寿命契約は残る。 |
| D02 | タスク・購読・要求の所有権と取消 | 未対応 | MiniAppTaskScopeでowner別Task取消、実行中の片方だけの取消、他owner継続、owner解放をunitで確認済み。CI隔離hostでの二Featureの起動・片方の取消・他方継続/正常完了は[34320179116](https://github.com/y-aplus/JibunKit/actions/runs/34320179116)で成功。呼出時点のTask群を取消して全完了を待つcancelAllAndWaitは[34323337796](https://github.com/y-aplus/JibunKit/actions/runs/34323337796)でunit/build成功。別batch維持とcleanup完了待ちも[34323800250](https://github.com/y-aplus/JibunKit/actions/runs/34323800250)で成功。MiniAppRuntimeで新規受付閉鎖・Task完了待ち・資源の逆順後始末を追加し、idle leaseとの接続は34371355575のunit・iOS該当テストで成功（run全体はWeb保持失敗）。終了待ち途中の受付拒否・Task cleanup完了待ち・owner解放時の順序は34377803005でunit成功。購読・要求全般と復元処理の接続は未完。 |
| D03 | クラッシュ・ハング・メモリとhelper extension | 未対応 | 協調的緩和は未対応。helperによる追加補完可能性は今回新たに発見した実装判断用の検証課題。 |
| D04 | 画面遷移・復帰・提示と複数scene | 未調査 | AppNavigation.sharedに一つのpathがあり、open時に置換。Feature/scene別の一般的な保持機構は確認できない。 |
| D05 | 画面外観・idle timer等のアプリ共有設定 | 未対応 | idle timerのFeature/操作別leaseを追加。他owner継続・同一owner複数要求・冪等release・解放時後始末のunitとiOS buildは[34366651143](https://github.com/y-aplus/JibunKit/actions/runs/34366651143)で成功。iOS共有設定の二Feature取得・片方解除・最終解除は[34367286197](https://github.com/y-aplus/JibunKit/actions/runs/34367286197)で成功（49.277秒）。Runtime終了時の自動解除接続は34371355575で成功（44.083秒）。実際の自動ロック・表示寿命との接続、外観設定全般は残る。 |
| D06 | UserDefaults・通常ファイル・DB配置 | 未対応 | MiniAppContextのUserDefaults namespaceとMiniAppFilesは実装・限定検証済み。DB、Keychain、Web/ネットワーク状態までの一般契約は別D項目を含め未完。 |
| D07 | 復元・移行・リセット中の処理停止 | 未対応 | 選択復元のstop/apply/resumeをDefinition経由でhostへ接続。製品BackupScreenで成功経路と停止・部分適用・再開・両失敗の4経路、他ownerのTask/データ維持を確認（34389357592）。プロセス共通の復元予約で重複planを変更前に拒否し、非重複は並行実行。予約解除と取消開始境界は34412140159でunit成功。複数owner途中取消の未着手保護、snapshot exportとの調停もunitで確認。実機JSON書出し・読込み・選択復元もユーザー確認済み。非同期資源解放待ちを追加し、復元との結合検証を進行中。実FeatureのDB接続・通常書込み・別processとの排他、移行/リセットへの適用は残る。[検証記録](verification/2026-09-10-runtime-lifetime.md)。 |
| D08 | Keychainと資格情報の削除範囲 | 未対応 | generic passwordのFeature/service別namespace、取得・更新・account削除・service内全削除を追加。native Keychainで同名accountのA/B分離と他service保持は[34337653973](https://github.com/y-aplus/JibunKit/actions/runs/34337653973)で成功（macOS、0.230秒）。iOS隔離hostで保存・再起動・A logout後のB保持は[34338195098](https://github.com/y-aplus/JibunKit/actions/runs/34338195098)の該当テストで成功（63.720秒、run全体は通知action回帰失敗）。iOS保持/logout再検証も34342836098で成功。native accessibilityの明示指定・変更・省略時保持は[34345684119](https://github.com/y-aplus/JibunKit/actions/runs/34345684119)でiOS属性読戻し成功。生体認証/アクセス制御・同期・署名変更後の継続は残る。 |
| D09 | URLSessionのcookie・認証・cache | 未調査 | defaultの共有Cookieとephemeralの非永続ストアをApple仕様で確認。同一server identityのCookie/credential/cacheと片方削除の隔離baseline unitを追加、CI待ち。永続ログイン・実通信・backgroundとの比較は残り、一律ephemeral化は行わない。[検証計画](verification/2026-09-10-network-isolation.md)。 |
| D10 | WKWebViewの永続Webデータ | 未対応 | Feature/profile別の安定UUIDと標準の永続WKWebsiteDataStore割当を追加。34348667212で保存後の再起動にCookie未検出。検証用WebViewへストアを割当・保持する形へ修正し[34351393142](https://github.com/y-aplus/JibunKit/actions/runs/34351393142)の該当テストで再起動保持・A全削除後のB保持が成功（65.811秒、run全体は通知操作失敗）。34359547457では再起動後Cookie欠落が再発。保存読戻しと通常background移行後の再起動を明示し[34362662224](https://github.com/y-aplus/JibunKit/actions/runs/34362662224)で成功（79.265秒）。34371355575ではCookie欠落が再発。ページnavigation完了を待って操作する検証へ修正し34373928804でCI全体成功。保存直後の強制終了耐性、WebView経由の実ページ・localStorage等・Feature削除時の寿命調停は残る。  34385366877で識別子付き/標準ストアの両方の再起動保持、A削除後のB保持をログ確認。過去の不安定性は原因未確定。[比較診断](verification/2026-09-10-web-data-persistence.md)。 |
| D11 | Web認証セッションと返却先 | 未調査 | 一般認証は未調査。既存の標準的なsession境界を壊さず使う対象。 |
| D12 | URL・Universal Link・外部ファイル受信 | 未対応 | 固定jibunkit URLと通知詳細routingは実装済み。一般URL callback、Universal Link、外部ファイル受信・security-scoped URL所有は未対応。 |
| D13 | 通知カテゴリ・action・foreground・取消 | 未対応 | notification request ID namespaceとpayload routingは実装済み。actionIdentifier/文字入力/消去の所有者配送unitと従来open実通知回帰は[34324423834](https://github.com/y-aplus/JibunKit/actions/runs/34324423834)で成功。categoryの所有者namespace・合成・衝突拒否は[34325938194](https://github.com/y-aplus/JibunKit/actions/runs/34325938194)でunit/build成功。所有者限定のpending/delivered一括取消とRecords接続は[34326889563](https://github.com/y-aplus/JibunKit/actions/runs/34326889563)でunit・独立/統合build成功。Feature別foreground方針と既定値維持は[34327561372](https://github.com/y-aplus/JibunKit/actions/runs/34327561372)でunit/build成功。動的category更新の所有者別置換・失敗時保持は[34328104046](https://github.com/y-aplus/JibunKit/actions/runs/34328104046)でunit/build成功。CI隔離hostの二FeatureでOS登録読戻し・更新/解除・再起動再登録は[34328684533](https://github.com/y-aplus/JibunKit/actions/runs/34328684533)で成功（39.750秒）、従来通知tap回帰も成功。foreground実通知の所有者別callback配送は[34331529826](https://github.com/y-aplus/JibunKit/actions/runs/34331529826)で成功（34.900秒）。独自actionのOS操作・所有者配送・他Feature表示維持は[34334411845](https://github.com/y-aplus/JibunKit/actions/runs/34334411845)で成功（39.602秒）。34338195098ではaction通知カード未検出で回帰失敗。画面遷移競合を避ける検証用表示方針・背景移行確認後、34340335666では通知カードを検出したがGrouped状態のままactionボタン未検出。先行foregroundテストの通知をowner限定で後始末し[34342836098](https://github.com/y-aplus/JibunKit/actions/runs/34342836098)でaction回帰成功（38.000秒）。34348667212で再びactionボタン未検出。34351393142でも通知コンテナ長押しでは未展開。取得した前後スクリーンショットで画面下部のstack表示を確認し、上スワイプ後も34354020916でaction未展開。予約前のnative category/action読戻しを必須にし、34356757243ではnative category/action読戻し成功、座標長押しでもaction未展開。本文付き通知と左スワイプのView経路で[34359547457](https://github.com/y-aplus/JibunKit/actions/runs/34359547457)のactionテスト成功（86.228秒）。foreground表示結果の共存検証は未完。 |
| D14 | APNs・remote pushの配送とサーバー識別 | 未調査 | 未調査。必要契約と署名可否を分け、SideStore全般で不可と一括推定しない。 |
| D15 | BackgroundTasksの起動登録・期限・completion | 未対応 | 未対応。現在のhost phase配送とは別機構。 |
| D16 | Background URLSessionの再接続 | 未対応 | 未対応。通常Task所有権だけではカバーしない。 |
| D17 | ユーザー起点の継続処理・進捗・取消 | 未対応 | 初期棚卸しのbackground領域へ追加すべきAPI種別。未対応。 |
| D18 | Spotlight・NSUserActivityと項目削除 | 未対応 | 初期棚卸しに明示されていない差分。未対応。 |
| D19 | 権限・プライバシー同意の単位 | 未対応 | 権限要求/拒否の一部例はあるが一般的なFeature別同意は未対応。 |
| D20 | 署名capability・Info.plist・構成の合成 | 未対応 | 現状Project.swift中心の手動設定。汎用的な要求合成は未対応。 |
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
- D06: UserDefaults namespaceとMiniAppFilesは実装・限定検証済み。DBや他の状態分離はD07–D11等で別管理する。
- D12/D13: URL/通知routingとnotification request namespaceの既存成果は維持する。一般callback、通知category/action等は未完として扱う。
