# Generated host regression triage

CI 34537802126、source `aeeadc9d05a205d2affcbe935c05153eb435c5e8`はD11のnative stepが成功した後、GeneratedFeatureUITestsの21テスト中3テストで計5 assertionが失敗し、run全体は時間上限でcancelledとなった。テストが既存であることは失敗原因が既知であることを意味しない。

## Records詳細URL: host修正・CI検証済み

`testRecordsUsesIndependentHostStorage`の通常row選択では本文を表示できたが、Counterからの`jibunkit://mini-app/records?destination=...`では本文を表示できず、815/816行の二assertionが失敗。保存値そのものの欠落はこのログからは示されていない。

同runのsimulator-app.log 23:05:37.896に、SwiftUIがUUIDの`navigationDestination`をNavigationStack外の配置として無視した記録がある。hostは一覧をstack rootにし、MiniAppIDを最初のpath要素としてFeature rootを生成していた。複数階層への一括URL遷移に対し、Feature固有のdestination登録が安定して利用できない構造だった。

選択Feature自体をNavigationStackのrootに置き、pathにはFeatureの詳細値だけを格納する。empty pathはFeature rootを意味し、rootの「ミニアプリ」buttonが一覧へ戻る。世代付きbinding、Feature別経路保持、不正destination拒否は維持する。Feature型の列挙や遅延timerによる二段階pushは追加しない。

回帰はRecords詳細URL、値ベース経路保持/stale binding、scene別navigation実体、生成Notesの切替を一つのfocused batchで確認する。通常hostの通知遷移も対象にする。Swift/XcodeはCIで検証し、ここでは未成功。

初回修正run 34542201985（source `b6e7ac7`）は共有159試験とnative build/IPAは成功したが、Records詳細から一覧へ戻りCounter行をtapした後も一覧が残り、counter.value取得で失敗した。詳細URLへは未到達。行のLabelを全幅の明示contentShapeにし、右側の余白からの選択と遷移完了待ちを回帰へ追加した。次回は行frame/hittableとタップ直前のスクリーンショットを記録する。現時点で失敗原因や修正成功は未確定。

再試行34543883790（source `b78459d`）も同じ選択で失敗したが、原因を示す画面を取得できた。`records-return-launcher`（exported `418D5424-E6F0-494D-81C4-7E947848F1FD.png`）でCounter行は下部検索バーに覆われている。行frameは `(16,796,370,52.33)`、`isHittable=true`だった。tap後のaccessibility treeには検索欄のKeyboard FocusedとKeyboardがあり、Counterではなく検索欄を押したことが確認できる。全幅contentShapeの追加を撤回し、テストで行全体を検索バーとnavigation barの間へスクロールしてからtapする。待ち時間の延長では回避できない座標の重なりであり、Records詳細URLの修正は引き続き未検証。

34545556537（source `3549c59`）では、補助処理がprefixだけで対象を判定したため、`miniapp.back-to-list`まで一覧行として扱い、Counter画面に存在しないCollectionViewをscrollして失敗した。これはテスト補助処理の誤り。Records回帰内の実際の一覧行操作だけが明示的にscrollを依頼する形へ変更し、戻るbuttonやFeature内操作には適用しない。

## 通知action: 未解決

`testNativeNotificationRequestPayloadsReachOnlyTheirOwners`のnotification cardは見つかったが、左swipe後のViewボタンを検出できなかった（611行）。そのためこのrunはnative action callbackの成功証拠ではない。OS画面操作と通知配置の証拠から追加調査する。D11のcallback処理との因果関係は未確認。

## Web再起動保持: 未解決

`testWebDataPersistsAndClearingPreservesOtherFeature`で、A/Bとも再起動前のnative cookie読戻しは成功したが、後の再起動読戻しでprofile/default両方がmissing（488行の二assertion）。`isPersistent=true`、`sessionOnly=false`、期限ありを記録している。識別子付きprofileだけの欠落ではなく、比較用default storeも同じ結果だった。原因未確定であり、JibunKitの分離に問題がないとも、単なるテスト不安定とも断定しない。

## 修正後の成功証拠

[34547138490](https://github.com/y-aplus/JibunKit/actions/runs/34547138490)、source `4c608c6d7ed781f8aa013964e81427498349eb8e` は成功。Feature rootをstack内容へ移す製品修正と、検索バーを避けるテスト操作を含む。

- testFeatureRootNavigationRegression: 214.357秒で成功。Recordsの保存/再起動/詳細URL・不正URL拒否、Counter値保持、Feature別経路の切替/戻る/reset/stale binding、二scene状態、生成Notesの切替、cold custom URLを確認。
- Counter行はscroll後frame `(16,663.33,370,52.33)` となり、右側余白のtapからCounterへ遷移した。
- 共有167試験、native build/IPA、生成Feature単独起動が成功。
- 通常host UI 11件: 385.061秒。通知配送/遷移29.822秒、添付ZIP復元77.354秒を含む。
- 独立したFiles経由の選択Counter復元: 126.136秒で成功。
- Recordsの既知Simulator Quick Lookはexpected failure。実機での確認済み範囲とは別に、Simulator未解決を維持する。

generated hostは上記batchだけであり全件成功とはしない。通知actionの反復操作とWeb保持の過去の不安定性はこのrunの完了対象外。通知は[別の検証](2026-09-11-notification-ui-regression.md)、Webは[終了時点比較](2026-09-11-web-cookie-termination-comparison.md)へ進んでいる。

## 通知の連続操作に関する追加証拠

[34547236843](https://github.com/y-aplus/JibunKit/actions/runs/34547236843)、source `b8e66168beb053f0309fd2825aee2c01c7efa000`で、独自action→foreground通知の配送/後始末→独自actionの順を一つのXCTestに固定して成功（187.611秒）。両回とも内容・所有者配送・他Feature表示を検証し、通知カードと展開actionの画像を保存した。製品callbackとOS操作gestureは変更していない。過去のOS表示失敗の原因は未確定であり、全generated suite成功の代替にはしない。[詳細](2026-09-11-notification-ui-regression.md)。
