# D05 scene選択とidle timer要求の接続

状態: 専用unit/iOS UIと、修正したRecords回帰を確認済み。部分補完としてmainへ統合。

## 補完する差分

Feature Aの表示中に取得した画面点灯要求が、Bへ切り替えてもhost全体へ残る差分を補う。任意の`MiniAppSceneIdleTimer`で要求の意図と実leaseを分離し、ownerが選択されたactive sceneがある間だけ有効にする。従来の明示lease契約は維持する。

## 検証計画

- 四つのunit: 選択離脱/復帰・背景化、他ownerの明示lease維持、複数sceneとforeignイベント、Runtime終了/閉鎖後の再取得拒否・同ownerの別scope維持、native apply再入中のclose後始末。
- 署名付き生成hostの`testSceneIdleRequestSuspendsResumesAndPreservesOtherOwner`: A要求、OS背景化時の解除と復帰、B選択時の解除、Bの明示要求を維持したA復帰とRuntime終了、B解除後の通常設定、A閉鎖後の再取得拒否。`UIApplication.shared.isIdleTimerDisabled`とowner集合を読み戻す。
- 共有/独立Feature・通常IPA・通常host通知遷移・Records回帰。Windowsではdiffと対象selectorの存在を確認する。

## 境界

Simulatorで共有設定を読み戻す試験であり、実機が放置後に暗転/ロックすることの検証ではない。二つのOS windowを操作する試験でもない。任意のViewやsheetの被覆、非協調的な直接setter、外観・輝度等の共有設定は残る。D05全体は未対応のまま。

## 初回runの証拠と別回帰の失敗

[34494488615](https://github.com/y-aplus/JibunKit/actions/runs/34494488615)、source `159bb56`では専用4unitを含む共有131テスト、専用scene idle UI（70.522秒）、通常通知遷移（46.487秒）、iOS build/IPA検査が成功した。run全体は後続の独立Records UI回帰で失敗しており、成功runとは扱わない。既知のSimulator Quick Lookのexpected failureも実プレビュー成功へ読み替えない。

Recordsの保存JSONには新規記録と本文が正常に存在したが、タップ後の動画とUI階層は一覧のままだった。合成tapは新規行の中央 `(201, 256.67)`。短いタイトル/本文はそれぞれx32–174、x32–133にあり、中央はラベルの空白部分だった。既存NavigationLinkラベルのVStackへ横幅と矩形のhit領域を明示し、中央の空白もリンク操作に含める修正を行った。試験は同じ中央tapのまま、編集ボタン/本文の出現を明示的に待って詳細遷移を確認する。二度目のtapや失敗skipは追加しない。原因仮説と修正の有効性は再runで確認する。

[34497999557](https://github.com/y-aplus/JibunKit/actions/runs/34497999557)、source `d0f4215b71d642848346c611ea8f3ed6f61698d5`が成功。Recordsの中央tapからの詳細表示・作成/取消/編集/再起動/検索/削除は72.081秒で成功。scene idle専用UIは72.461秒、通常host検索は37.099秒、生成standaloneは10.027秒で成功した。共有131テスト・iOS build/IPAも成功。Records添付試験は89.931秒で通過したが、Quick Look表示は既知のexpected failureを含むので成功扱いしない。
