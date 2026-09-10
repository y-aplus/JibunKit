# Sceneとナビゲーションの所有権

## 現在の契約

`JibunKitApp`のWindowGroup内にある`MiniAppSceneRoot`が、自分の`AppNavigation`を`@State`で保持する。App単位のsingleton NavigationPathを廃止した。各rootの検索・backup sheetも既存のview状態としてそのsceneに属する。sceneに届いた`onOpenURL`は、そのsceneのnavigationへ直接渡す。

process単位の通知には対象sceneが直接渡されないため、`AppSceneRouting.shared`が`MiniAppSceneRouter`で配送先を選ぶ。これは経路そのものを共有するオブジェクトではない。各rootは表示時に登録し、sceneのactive変化を更新し、非表示時に登録解除する。handlerはnavigationを弱参照し、登録が画面の寿命を延ばさない。

配送規則は次のとおり。

- 登録中でactiveなsceneを優先し、複数あるときは直近にactiveへ移ったsceneを選ぶ。同じactive値の再通知では順序を変えない。
- activeがなければ、最後に登録またはactive化された残存sceneへ渡す。これはwindowをOS上で前面にする操作ではない。
- sceneがまだない場合、最後に要求された行先を保留し、最初の登録時に渡す。nilは「一覧へ」の明示要求として保持する。
- 一件の要求を複数sceneへ同報しない。handler中の追加要求は現在の配送後に再選択する。解除された登録は次の選択に使わない。
- 通知のcustom action/dismissは既存のFeature所有者配送を保ち、画面選択処理へ渡さない。

## 同じscene内のFeature切替

`AppNavigation`はMiniAppID別の`NavigationPath`をscene内で所有する。画面下部の「ミニアプリを切り替え」から他Featureを選ぶと、対象の最後の値ベースの経路へ戻る。「ミニアプリ一覧」も経路を保持し、一覧から再度選択すると復帰する。通常の戻る操作は経路を一段ずつ戻す操作であり、戻した詳細を自動的に復活させない。「このアプリの最初の画面へ」は選択中のFeatureだけをrootへ戻す。

行先なしのURL/通知は従来どおり対象Featureのrootを明示的に開く（切替メニューによる経路再開とは区別する）。具体的なdestinationを持つURL/通知は、Integrationによる検証に成功した場合だけ、そのFeatureの経路を指定先へ置換する。不正/非対応のdestinationは表示中・保存中の経路を変更しない。他Featureの経路は維持する。

切替メニューはNavigationStack外のsafe areaに置き、Featureの詳細画面やtoolbar構成に依存せず表示する。Featureの内容へ重ねず、その表示領域を確保する。

Stackの識別子とbindingの世代を切替時に更新する。同じSwift型のnavigation valueを異なるFeatureが使っても、前のstackのdestination登録を再利用しない。離脱したstackのbinding更新は、同じFeatureへ戻った後も新しい経路へ適用しない。

これはメモリ上の値ベースの経路保持であり、`NavigationLink(value:)`と`navigationDestination(for:)`を対象とする。Viewを直接指定するNavigationLink、View内の入力状態やsheet、任意のUIKit stack、アプリ終了後の経路復元は今回の補完範囲ではない。`Hashable`値に`Codable`を要求せず、Featureの画面型をhostで列挙しない。34484074366で専用UI（79.425秒）と通常通知・Records回帰が成功。統合sourceの検証状況は[Feature経路保持](verification/2026-09-10-feature-navigation.md)に記録する。

## 根拠と検証

[Apple WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)はwindowのview階層内に置いたStateへwindow別のstorageを割り当てる。[ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)はView内で読むと当該scene、App内では全sceneの集約になる。Featureへの既存host phase配送はApp内の集約を維持する。root view内のphaseは通知先選択と[Feature別のscene活動通知](guides/scene-feature-activity.md)へ用いる。

[MiniAppSceneRouterTests](../Tests/JibunKitCoreTests/MiniAppSceneRouterTests.swift)は選択・非同報・phase変化・登録解除・起動前の保留・再入時の順序を検証する。CI専用iOS画面は実際のAppNavigationを二つ作り、片方の詳細pathや通知先の変更が他方のpathを消さないことを確認する。通常hostでは実通知からの遷移を回帰検証する。[34440565104](https://github.com/y-aplus/JibunKit/actions/runs/34440565104)でunit、iOSの二navigation実体の非干渉（52.260秒）、通常hostの通知遷移（68.971秒）、IPA/Feature/Records検証が成功。

## 残る差分

二navigation実体の試験は、OSの二つのwindowを操作する試験ではない。iPadOSの複数windowを有効にするscene manifest、window生成・破棄・前面化の運用、scene session identifierを用いた明示配送は未実装/未検証。これはOSにより不可能と判定した制約ではない。

同じsceneでFeatureを切り替えた際の各FeatureのView内入力状態保持、複数sheet要求の所有者/調停、UIViewControllerによるrootの接続契約も残る。今回の変更だけでD04全体を完了とはしない。OSによる永続的な全画面状態保存も保証しない。

## 検証経過

[34440305199](https://github.com/y-aplus/JibunKit/actions/runs/34440305199)（source `26a5d45`）は共有テストのコンパイルで失敗。CoreだけをimportするテストがCounterFeatureで定義されるMiniAppID.counterを参照していた。Coreテストは専用の明示IDへ変更し、同じ参照を持つiOS確認画面もMiniAppID("counter")へ変更した。CoreにCounterFeatureの依存は追加しない。このrunではscene routerの実行試験・iOS build/UIへ到達していないため、変更全体の検証待ちは継続する。

34440565104（source `6a4d2fd`）で修正後のCIが成功。scene routerのcold start・選択/解除・再入の3unitも成功した。実window操作の証拠へ読み替えない。
