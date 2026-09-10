# D01 scene別のFeature活動通知

状態: 共有unit・署名付きiOS専用試験・通常回帰が成功。部分補完としてmainへ統合。

## 対象と実装

host集約phaseだけでは、非表示Featureも活動中と取り違える。`MiniAppSceneActivityDispatcher`をWindowGroup内のrootが所有し、接続ごとのUUID、scene phase、Feature選択をDefinitionの任意callbackへ配送する。Featureをhostのswitch文で列挙しない。非選択でもRuntimeは終了させず、既存のhost集約callbackを維持する。

## 検証

- Foundationの4試験: 未生成/選択Featureのphaseと選択差分、二sceneの片方だけの終了と再接続世代、再入disconnect/connectの全owner配送順、重複抑止と非選択によるRuntime非終了。
- 生成hostの`testSceneActivityFollowsSelectionAndBackgroundWithoutStoppingOtherWork`: A選択/B未生成、Aで継続Task開始、B選択後のA継続、OS home操作による背景化と復帰の両owner配送、一覧とA再選択を確認する。
- 共有/独立Feature、通常IPA、通常host通知遷移も回帰対象。WindowsにはSwift/Xcodeがないため、ローカルではdiff検査のみ。

## 未確認・残存

UIKit/SwiftUIの実window二つを同時に操作する試験ではない。モデル二つの独立性と一つのnative sceneの通知を分けて記録する。rootの接続UUIDはOS session識別子ではない。任意Viewの入力状態、sheetでの被覆、Feature実行instanceの生成/終了やRuntimeとの自動接続は今回の範囲外。D01全体は未対応のまま。

## 初回CIと修正

[34491312333](https://github.com/y-aplus/JibunKit/actions/runs/34491312333)、source `d513135`は共有テストのコンパイルで失敗。登録をタプル配列で渡すと、内部のクロージャがMainActor/Sendableとして推論されず、非Sendable関数からの変換を拒否された。Coreのdispatcher本体はコンパイルされたが、unit実行・iOSビルド・UIには到達していない。

公開の`Registration`初期化子へ型付きMainActor handlerを渡す形に変更し、hostとunitの登録箇所もそろえた。unsafeなSendable適合や並行性チェックの緩和は追加しない。mainへ入ったテスト指定の事前/実行後検査も取り込み、修正後のnative試験で併せて検証する。

## 修正後の証拠

[34491955629](https://github.com/y-aplus/JibunKit/actions/runs/34491955629)、source `6729452c1e9ce4dc4a7a63d315707a06f6f7bb9b`が成功。専用4unitは0.001秒、共有127テストは失敗0。署名付き生成hostのscene活動UIは35.264秒で、A/B選択・未生成Bへの配送・OS背景化と復帰・非選択AのTask継続が成功した。通常hostの実通知遷移は36.807秒で成功。両UIについて追加したtest selectorの成功後検査も通過した。

独立Feature/生成standalone、通常app/Widgetビルド・IPA検査、Records回帰も成功。限定filterのrunであり、Filesバックアップ往復や全UI suiteの成功を主張しない。mainの後続差分は任意Spotlight fixtureのCI接続だけで、活動通知の製品sourceを変更しない。OS上の複数window実操作と実機検証は未実施。
