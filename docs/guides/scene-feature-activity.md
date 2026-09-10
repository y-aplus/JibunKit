# Featureの選択状態とsceneの活動状態

独立アプリでは自分のsceneの活動を観測できる。統合後はhostがactiveでも自分のFeatureが選択されているとは限らない。`MiniAppDefinition.onSceneActivityChange`で両者を区別してIntegrationへ渡す。既存の`onHostPhaseChange`は全sceneの集約通知のまま維持する。

```swift
MiniAppDefinition(
    id: featureID, title: "My Feature", systemImage: "app",
    onSceneActivityChange: { activity in
        // Another scene may still use this Feature; track each connection.
        if activity.isConnected {
            model.sceneActivity[activity.sceneID] = activity
        } else {
            model.sceneActivity.removeValue(forKey: activity.sceneID)
        }
    }
) { context in
    FeatureRoot(model: model)
}
```

`featureID`は永続的なFeature識別子、`sceneID`はhost rootが接続されている一回の寿命のUUID。OSの永続scene session IDやFeature Viewの生成世代ではない。rootが再接続されると新しいUUIDになる。`phase`はそのsceneのactive/inactive/backgroundで、nilは接続終了を表す。終了時は`isSelected`もfalseになる。rootがまだ作られていないFeatureのIntegrationにも初期状態を届ける。

`isSelected`はhostの経路がこのFeatureを選択していることだけを表す。背景化しても選択は維持される。sheetに隠れたか、画面の何割が見えているか、キーボードのfocusがあるかは表さない。一覧では全Featureが非選択になる。値ベースの詳細遷移は選択を変えない。

通知はMainActor上で同期配送し、同じ状態は重複配送しない。ハンドラ内の再入でも一つの遷移を全ownerへ配送してから次へ進む。ハンドラは速やかに戻し、重い処理はFeatureの所有するTask等へ移す。非選択や背景化を一律のRuntime終了へ変換しない。継続が必要な通信・再生等の扱いはFeatureが決め、複数sceneがある場合は残っているsceneも考慮する。

単一processのOS実行時間は増えない。強制終了前のcallbackや、OS上の複数window生成・破棄の検証完了も保証しない。現時点のhost接続終了はrootの`onDisappear`に結び付く。OS scene sessionの永続化やFeature実行instanceの明示生成/終了、任意のView内状態保持は別の補完単位である。

根拠: [Apple ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)はView内のphaseとApp内の集約phaseを区別する。本APIはそれへFeature選択の情報を追加する。[検証記録](../verification/2026-09-10-scene-feature-activity.md)。
