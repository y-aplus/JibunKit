# AlarmKit 接続ガイド

JibunKit の AlarmKit 境界は、アラームを汎用 timer/payload に変換しない。Feature が具体的な `AlarmMetadata`、`AlarmAttributes`、表示、schedule、ボタンの意味を所有し、`MiniAppAlarmCoordinator<Native>` は owner・業務世代・registration・OS UUID の照合だけを担う。最低OSは iOS 26 である。

## Feature の組込み

1. Feature 固有の `AlarmMetadata` と `AlarmManager.AlarmConfiguration<Metadata>` を作る。固定日時は `.fixed(Date)`、タイムゾーン追従の時刻と週次繰返しは `.relative`、即時 countdown は `countdownDuration` と `schedule: nil` を使う。
2. app process に Feature ごとの `MiniAppAlarmCoordinator<MiniAppAlarmKitNative<Metadata>>` singleton を一つ置く。app と `LiveActivityIntent` は同じサービスへ到達させ、extension から別 coordinator で新規登録しない。
3. `MiniAppContinuingJournal(owner:namespace:containerURL:)` を `MiniAppAlarmJournalStore` で包む。これはOS対応表であり、Featureのbackup payloadへ入れない。
4. admission closure で、その owner が受付中であることと `localID` の現行業務世代を検証する。OS許可はapp全体、admissionはFeature単位であり、同じ概念ではない。
5. coordinator の `surface()` を `MiniAppDefinition.continuingSurfaces` に登録する。親hostで共通プロパティが利用可能になるまでの接続形は `Tests/ContinuingAlarms/DefinitionConnection.swift.fragment` に示す。

`schedule` のconfiguration closureには、完全な `MiniAppContinuingIdentity` と、先にjournalへ保存済みのOS UUIDが渡る。これらをstop/secondary Intentへすべて埋める。古いgeneration、別registrationID、別systemIDは拒否される。

## 操作と失敗保証

- `schedule`: native呼出し前に `.starting` を保存し、native成功後だけ `.active` にする。途中失敗の記録は消さない。
- `replace`: 新UUIDを登録してから旧UUIDを `.ending` にしてcancelする非原子的操作である。旧cancelが失敗した場合は新旧両方をjournalに残し、`partialReplacement` と両UUIDを返す。即時countdownも同じく扱い、初版という理由では拒否しない。
- `stop` / `cancel` / `countdown` / `pause` / `resume`: AlarmKitへ渡しただけでは成功ACKとしない。boundedな再読出しで消失または期待stateを確認し、未収束は `nativeDidNotConverge` として残す。
- `reconcile`: cold launch時にjournalと `AlarmManager.shared.alarms` を照合する。`.starting` かつOSに存在するものは回収し、`.ending` かつ消失済みのものは完了する。期限切れ・消失済みアラームを暗黙に再登録しない。
- 未知のOS UUIDは `unknownSystemIDs` に診断表示するだけで、ownerを推測せず、cancelもしない。同じ `AlarmManager.shared` を使う別Featureの登録であり得る。
- `close` は通常受付を閉じて進行中処理をdrainする。`endOwned` は通常のSharedState readに依存せず、journalに載る当該ownerだけを管理中にcancelする。`open` は受付を戻すだけで過去の予定を再発火しない。

標準stop/countdownボタンの状態遷移はOSが行う。`stopIntent` は追加のFeature callbackであり、同じ `AlarmManager.stop(id:)` を重ねて呼ばない。coordinatorの `handleSystemIntent` はadmission、generation、registrationID、OS UUIDの一致を確認してからFeature eventを実行する。

## target と plist

app targetには空でない、ローカライズ済み `NSAlarmKitUsageDescription` が必要である。countdownを提供する場合は `NSSupportsLiveActivities = YES` と、同じ `AlarmAttributes<FeatureMetadata>` を登録するWidget extensionが必要になる。AlarmKit専用entitlementを推測で追加しない。App GroupはJibunKitのjournal/Feature状態共有の要件であり、AlarmKit自体の要件ではない。

fixtureの公開接続点は次のとおり。

- `FeatureAAlarmMetadata` / `FeatureBAlarmMetadata`: 異なる具象metadataと表示
- `featureAAlarmRuntime` / `featureBAlarmRuntime`: app-process singleton
- `AlarmDiagnosticViewFactory.featureA()` / `.featureB()`: 通常hostへ差し込む診断View
- `FeatureAAlarmLiveActivity` / `FeatureBAlarmLiveActivity`: countdown用Widget
- `ContinuingAlarmIntents` と `ContinuingAlarmFixtureIntents`: Intent metadata package
- `AlarmFixtureHost.swift`: 独立A/B/Combinedで共用するhost例（targetごとに必要なFeatureだけを列挙してよい）
- `AlarmFixtureWidget.swift`: Combined WidgetBundle。独立targetでは該当するWidgetだけを登録する
- `Info.plist.fragment`: app plistへ合成する二つの必須キー

A/Bはどちらも `localID == "same-id"` を使う。identityはownerを含むため衝突せず、Aのreset・取消・部分失敗でBを消さない。fixtureのresetは当該Featureの業務世代だけを更新し、OS登録や他Featureを破壊しない。

## 検証

Foundation fakeでは、native登録前journal、schedule失敗、非原子的replaceの部分成功、古いgeneration/registrationID拒否、cold reconcile、未知OS UUID保持、bounded未収束、A cleanup時のB保持を検査する。fakeは契約logicの試験用で、AlarmKit実機試験の代替ではない。

Xcode 26 / iOS 26 SDKでは、strict-concurrency build、AppIntent metadata、app/extension plist、独立A、独立B、Combined、通常hostを確認する。実機では許可、固定/週次/countdown、pause/resume/stop/cancel、標準stop callback、cold launch、再起動、Focus/silent、片側無効化/削除/復元失敗後のB保持を確認する。Windows上の静的検査をSwift/Xcode/AlarmKit実行済みとして扱わない。

## Apple一次資料

- [AlarmKit](https://developer.apple.com/documentation/alarmkit)
- [AlarmManager](https://developer.apple.com/documentation/alarmkit/alarmmanager)
- [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [AlarmManager.AlarmConfiguration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration)
- [Alarm.State](https://developer.apple.com/documentation/alarmkit/alarm/state-swift.enum)
- [WWDC25: Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)
- [NSAlarmKitUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription)
