# D01 scene別のFeature活動通知

状態: 実装済み、CI確認待ち。main未統合。

## 対象と実装

host集約phaseだけでは、非表示Featureも活動中と取り違える。`MiniAppSceneActivityDispatcher`をWindowGroup内のrootが所有し、接続ごとのUUID、scene phase、Feature選択をDefinitionの任意callbackへ配送する。Featureをhostのswitch文で列挙しない。非選択でもRuntimeは終了させず、既存のhost集約callbackを維持する。

## 検証

- Foundationの4試験: 未生成/選択Featureのphaseと選択差分、二sceneの片方だけの終了と再接続世代、再入disconnect/connectの全owner配送順、重複抑止と非選択によるRuntime非終了。
- 生成hostの`testSceneActivityFollowsSelectionAndBackgroundWithoutStoppingOtherWork`: A選択/B未生成、Aで継続Task開始、B選択後のA継続、OS home操作による背景化と復帰の両owner配送、一覧とA再選択を確認する。
- 共有/独立Feature、通常IPA、通常host通知遷移も回帰対象。WindowsにはSwift/Xcodeがないため、ローカルではdiff検査のみ。

## 未確認・残存

UIKit/SwiftUIの実window二つを同時に操作する試験ではない。モデル二つの独立性と一つのnative sceneの通知を分けて記録する。rootの接続UUIDはOS session識別子ではない。任意Viewの入力状態、sheetでの被覆、Feature実行instanceの生成/終了やRuntimeとの自動接続は今回の範囲外。D01全体は未対応のまま。
