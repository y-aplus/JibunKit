# P2-B: 背景実行・位置の通常接続

2026-09-17開始。baselineは0.8.3の公開後commit `23c4fd1`（製品tagはc5afccc）。対象はplan.jsonのP2-4/D15–17、P2-3/D25。親は統合・host/生成/CI・証拠を担当し、背景と位置の独立した実装を各Sol low taskへまとめて渡す。診断ごとのCIや親子の小API単位のレビュー往復は行わない。

## 共通契約

- iOS26以上。既存MiniAppID、FeatureLifetime/Runtime、launch registrations、Feature同意、管理/復元を再利用する。通常API・native構成を保ち、単一scheduler/managerへの強制移植で本来の機能を狭めない。
- OS許可・署名・背景mode・起動時登録の条件と、Featureごとの受付/所有/取消/再接続を分ける。複雑さやサンプル不足を不能の根拠にしない。Apple一次資料と現SDK宣言を確認する。
- 操作世代、停止中/許可待ち/callback遅着、部分失敗、cold起動、他ownerの非初期値保持を対象にする。管理/選択復元は業務状態を変更しても勝手にOS活動を再開しない。削除/取消が他ownerの登録や成果を消してはいけない。
- Featureは業務データとnative仕事を所有し、JibunKitは統合で失う登録/配送/所有境界を補う。nil/default値だけを検査するfake試験で完了とせず、実Feature定義を通す自動回帰と実SDK接続を含める。
- UIの単なる非表示はscene切断ではない。実sceneの活動/選択を使う。停止はnative終了とcallback配送をjoinし、古い世代の仕事を新runtimeへ配送しない。

## 背景レーン（P2-4）

所有path: 既存CoreのBackgroundTask/SharedRefresh/BackgroundExecution/BackgroundURLSession関連ファイルと対応Core tests、必要な`Sources/JibunKitCore/Background/`、`Tests/P2Background/`、`docs/guides/background-*.md`、`docs/delivery/P2-background-proposal.md`。位置・host/Project/Package/workflow/台帳は編集しない。

既存BGTask API/shared refresh journal/background URLSession registryをまず評価し、作り直さず通常入口を完成させる。refresh/processingの受付・launch・expiration・cancel・completion、cold起動、転送再接続/全event完了、重複配送・他owner保持を接続する。iOS26の通常継続処理も標準APIの可用条件に照らして扱う（特殊GPUや万能schedulerは対象外）。OS起動の非決定性をJibunKitの不具合と混同せず、手動handler呼出しをOSによる起動の証拠としない。

診断入口は`P2BackgroundProbe.definitions`、native testは`Tests/P2Background/P2BackgroundNativeTests.swift`。起動時の必要登録は既存公開hookに組込み、hostの共有変更が必要なら具体的な宣言と呼出し位置を提出する。実背景転送fixtureは既存HTTP診断を再利用できるか判断し、外部server/端末でのみ可能な条件を明示する。

## 位置レーン（P2-3）

所有path: `Sources/JibunKitCore/Location/`、`Tests/JibunKitCoreTests/Location/`、`Tests/P2Location/`、`docs/guides/location.md`、`docs/delivery/P2-location-proposal.md`。背景レーン・host/Project/Package/workflow/台帳は編集しない。

前景/背景位置、通常geofence/iBeacon、許可変更・再起動、owner別の登録/解除/配送、監視枠不足の説明を扱う。位置の標準設定や要求精度を消す一律APIにしない。iBeacon受信機材や移動など実機条件は明示し、Simulatorのmock位置を物理的な背景起動と偽らない。OS共有枠の上限を調べ、予約/登録失敗/解除で説明可能な結果を返す。大量枠の透過仮想化・予測最適化は後段。

診断入口は`P2LocationProbe.definitions`、native testは`Tests/P2Location/P2LocationNativeTests.swift`。Feature別同意とOS許可を分離する。Feature側から全appの位置登録を取消すAPIを使わず、native manager/登録ID/世代の所有を明示する。

## 一括提出・統合検証

各担当は設計判断、実装、実Feature診断、Core/native回帰、接続ガイド、合格条件とtest対応、未検証条件をまとめてcommitする。ローカルでできる検査を行い、iOSが実行できなければ未実行と記載。共有ファイルの変更要求だけを別記し、独自のCI投入/IPA公開/版更新/main変更は行わない。権限設定を変更・上書きしない。依存する重大な契約衝突だけを親へまとめて通知し、それ以外は担当内で判断する。

親は両提出を一括レビューし、必要な修正をまとめて返す。診断hostの登録/usage descriptions/background modes・通常IPA・全対象試験の実行確認を統合する。CI初回予算3run、通常25分見込み/30分目標。正確なworkflow入力/filter/再利用source/準備upload込み見積りは提出後・投入前のreportで固定する。遅くとも3失敗までに切り分ける。OS監視で完了を一回受け、モデルpollと`gh run watch --interval`は禁止。

実機は今回新しく成立するOS起動・背景/位置イベントと代表操作へ絞る。状態・失敗・管理/復元・他owner保持の組合せは自動化し、0.8.3で成功した音声/撮影全手順を繰り返さない。機材や利用条件の重要な未確定事項は、調査と代替可能範囲を示してからユーザーへ確認する。
