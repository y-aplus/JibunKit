# P1-B 通知・HTTP・Webと0.8.0候補の契約

以下は着手時の契約・分担を保持した記録。対象別のCI・実機確認は完了し、現在の出荷状態は[0.8記録](../verification/2026-09-15-0.8-release.md)と[plan.json](plan.json)を参照する。本文の予約・未確認は当時の条件である。

2026-09-14開始。共通製品baselineはmain `099babd`（P1-A非実機gate通過、製品検証77b5f5d）。この契約commitを全レーンへ渡す。公開0.7.0は変更せず、P1-AのOS確認を含む0.8候補で一括実機確認する。Issue #6を受領済みで、1.0正式境界は0.8完了時にユーザーと確定する。

## 担当と編集権

最大3レーン。親はP1-4通知と共通統合、別のCodex開発スレッドSol lowがP1-5 HTTP、別のSol lowがP1-6 Webを担当。子CI・サブエージェント・追加スレッドは禁止。親から初回契約と一括修正を基本とし、小APIごとの逐次相談は行わない。

- 親: Core/Definition/Context/Runtime/Registry/Package/Project/workflow/台帳など共通契約ファイル、通知関連Core/tests、P1NotificationsProbe/UITests、通知ガイド。通知のforeground方針、action/text input、添付の寿命、cancel/delete/failure時B保持を通常Definitionへ接続。
- HTTP: `Tests/TemplateIntegration/P1HTTPProbe.swift`、`P1HTTPUITests.swift`、必要な専用HTTP fixture/tests、`docs/guides/feature-http.md`。修正が必要な場合はCoreのMiniAppCookieStore.swift、MiniAppPasswordCredentialStore.swift、MiniAppKeychain.swiftと対応testsを所有。共通MiniAppContext/Runtime/Registry/workflow、既存network_server.pyは親所有で、必要差分を提出時に一括提示。
- Web: `Tests/TemplateIntegration/P1WebProbe.swift`、`P1WebUITests.swift`、既存WebAuthenticationNative/WebStorageOwnershipの専用fixture/tests、`docs/guides/web-storage-ownership.md`、`web-authentication-ownership.md`。CoreのMiniAppWebData.swift、MiniAppWebAuthentication.swift、MiniAppRuntime+WebAuthentication.swiftと対応testsを所有。HTTP/Keychain/共有manifest/workflowへ直接変更しない。

新しい基盤APIが不可欠なら担当内で必要性を示すが、兄弟に新しい共通契約への追従を強いない。親所有ファイルの正確な変更案を提出する。既存wrapperを重ねるための新しい層を作らず、通常のSwift/Apple APIを所有・調停へ接続する。FeatureにCore依存を一律強制しない。

## 共通の通常接続

各ペアのowner IDは `p1-http-a/b`、`p1-web-a/b`、`p1-notification-a/b`。普通のMiniAppDefinitionを2件定義し、通常RegistryのMiniAppManagementだけを使う。第二の管理オブジェクトやテスト専用経路で無効化を代替しない。UI起動は `jibunkit://mini-app/<owner>` または一覧検索で行い、長いlazy Listの画面内配置を仮定しない。

業務Storeと接続はFeature lifetimeに保持し、画面を離れても必要な処理を保つ。通常アクセスはownerのStoreAccessへ参加し、async処理の実終了まで予約を保持。停止は新規受付を閉じてTask/callbackをdrainし、削除は予約済みのownerのデータのみ冪等に消す。削除内から通常store accessへ再入しない。管理状態を見ずに起動時seedして削除後の値を復活させない。

エラー/取消を空値や成功に置換しない。故障は旧データを保持し、成功後のACKだけ失敗する場合は二重適用を防ぐ。Aを操作してB値/資格情報/HTTP cookie/Web data/通知を変えない。UIは準備中・処理中・結果を区別し、同一List行の複数Buttonは操作が混線しないstyleを指定。破壊確認は明示的な取消を持つalertを使う。操作のassertionは実データと状態を確認し、文字列表示だけを内部保証に拡大しない。

## 各レーンの受入

HTTP（P1-5/D08/D09）: 実URLSessionとローカルHTTP serverを使い、同じorigin/account名のA/Bを分離して認証/永続Cookie/cacheの応答を確認。保存・再起動保持、取消/接続失敗/保存失敗時旧状態、ログアウト前のwriter停止、停止後logout、A削除/無効化の拒否とB保持を普通のFeature操作で通す。fixture-onlyのUserDefaults値比較で実HTTPを代替しない。固定fixture値だけを使い、ユーザーの実資格情報を要求しない。Keychain access-controlの既存実機確認済み契約を弱めない。非パスワード資格情報や専門的認証の一般化は別段階。0.8実機では再起動/IPA上書き/署名更新と保持・logoutを一括確認する。

Web（P1-6/D10/D11）: 実WKWebViewのCookie/localStorage/IndexedDBを通常store/lifetime/managementへ接続。A/Bの同じページoriginからの書込、再起動、片側消去/削除と他方保持、書込中の停止/取消/失敗を確認。Web認証はASWebAuthenticationSessionの実UI開始/取消/正しい返却先を維持し、Aが占有/終了/失敗してもB要求や状態を壊さない。既存direct Apple baseline4件の実証を再利用/拡張し、直接callback注入だけでOS成功と言わない。全SSO/関連domain HTTPS callback/全Web data/複数scene一般化はこの境界で勝手に完成扱いしない。

通知（P1-4/D13）: ownerごとのforeground方針が他方の通知に影響しないこと、通常actionと文字入力、添付ファイルの準備/登録/取消/削除/失敗の寿命、同名ローカルIDでも他ownerの予約と配信済み通知を保持すること。native通知は即時配送を保証せず、登録/OS配送/操作結果を区別。全APNsや全通知配送条件はP1の範囲外。

## 検証・提出・CI境界

各担当は上記一式を揃えてlocal commitし、`work/p1b-submission.md`にcommit/変更契約/合格条件とtest名/ローカル結果/未検証/親の共有編集案/正確なCI入力案を記載する。最終応答は別の `work/p1b-final-response.txt` に外側の管理が保存し、提出書を上書きしない。親への完了通知は外側のOS処理がqueueへ一回送る。途中で承認設定・sandbox設定を追加しない。WindowsでSwift/Xcodeが動いたとは報告しない。UIはXCTestのMainActor/Swift6隔離、OptionalなAPI戻り値、native cleanup待ちをsourceでレビューする。

初回CI予算3run。小さな失敗/子提出ごとにdispatchせず、全レーンの共有編集を親が統合し、1回のレビューで契約を揃えてから開始。normal/generatedの同一run並行matrixを初めて実動検証する。現在の実績からnormal29分、generated23分が基準だが、P1-B selectors追加後に再見積りし、30分を超えるnative Web認証は独立jobへ分ける。各job上限45分、nativeの既存短い上限は維持。fixtureと通常hostが共通buildを使える構成を優先し、重複する巨大なGeneratedFeatureUITestsクラス全体を選ばない。

P1-Aの262/13+Files/3P1 UIとnative8/7/23の証拠はsourceごとに差分レビューし、変えた契約の範囲だけ再検証する。P1-B初回前に全selector・期待値・job時間をevidence preflightへ固定。正常終了でも必要なassertion/実行ログがない条件を合格にしない。0.8候補でP1-AとP1-Bの実機操作をまとめ、minor文書監査とIssue対応を行う。必要な本質的ユーザー判断が出た場合だけ質問し、複数判断/実機操作依頼はntfyで通知する。
