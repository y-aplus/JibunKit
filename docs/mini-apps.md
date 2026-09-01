# ミニアプリの追加

AppbaseIOSのミニアプリは、ビルド時にSwift Packageへ組み込む。動的プラグイン、任意のIPA読込み、ミニアプリストアは0.1の対象ではない。

工程3で追加したリマインダーが、保存・画面・通知を持つ最小の実例である。追加時は、ホストへ個別処理を散らさず、安定ID、feature、画面、登録、必要なsystem surfaceの順に変更する。

## 通常の画面を追加する

1. `Sources/AppbaseCore/MiniAppID.swift`へ重複しないcaseを追加する。caseのraw valueは保存namespace、通知request ID、通知payloadの遷移先にも使うため、公開後に安易に変更しない。
2. `Sources/<Name>Feature`へ保存・更新処理を置き、`Package.swift`へtargetを追加する。共有保存が必要なら`SharedGroupResolver`を使い、キーは`MiniAppID.<case>.storageKey("...")`から生成する。別ミニアプリのStoreやキーへ依存させない。
3. `Sources/AppbaseIOS`へSwiftUI画面を追加する。
4. `Package.swift`の`AppbaseIOS` targetへfeature依存を追加し、`MiniAppListScreen.swift`の表示名・アイコン・destination mappingへ1件登録する。一覧そのものは`MiniAppID.allCases`から生成されるため、個別の一覧行は追加しない。
5. `AppbaseCoreTests`でID、保存namespace、通知request IDの一意性を、統合テストで同じUserDefaults suite内の保存値が互いを変えないことを確認する。

リマインダーでは、`ReminderStore`が`reminder.message`だけを扱う。カウンターの`counter.value`とは同じApp Group内でもキーが分かれ、統合テストで独立した保存と再読込みを確認している。

## ローカル通知も追加する

通知の受け取り口はホストに1つだけ置く。既存の`NotificationAppDelegate`が起動時にnotification centerのdelegateを設定し、通知payloadのミニアプリIDを`AppNavigation`へ渡す。新しいミニアプリのためにapp delegateを増やさない。

通知を予約する側では、次を守る。

- request IDは`MiniAppID.<case>.notificationRequestIdentifier`を使う。
- payloadには`MiniAppNotificationRoute.miniAppIDUserInfoKey`とミニアプリIDのraw valueを入れる。
- 通知許可は、通知を使うと利用者が選んだ操作の中で確認・要求する。アプリ起動時には要求しない。
- 拒否はクラッシュや全画面エラーにせず、そのミニアプリの通常操作を続けられる結果として扱う。
- 未登録・古い・不正なpayloadは別ミニアプリへ推測で遷移させず、一覧へ戻す。
- `UNTimeIntervalNotificationTrigger`の時刻は予約条件であり、正確な表示時刻を保証するものとして説明しない。

リマインダーの`ReminderNotificationScheduler`は、画面の「10秒後に通知」からだけ許可を要求し、`reminder`をpayloadに入れる。foregroundでも通知を表示し、通知タップは同じdestination mappingでリマインダー画面を開く。

## WidgetやApp Intentを追加する場合

通常画面の追加だけなら、Widget extensionやApp Intentの宣言は不要である。

Widgetを追加する場合は、別extension target、Widget bundleへの登録、extensionの`Info.plist`、本体と同じApp Group entitlement、IPAへの組込み検査が追加で必要になる。共有値はfeatureの同じStoreを通して読む。現在のカウンターWidgetが実例である。

App Intentを追加する場合は、Intent型と`AppShortcutsProvider`へのphrase登録に加え、Xcodeが生成するApp IntentsメタデータをIPAへ含める必要がある。現在のxtool 1.17.0ローカル経路ではこのメタデータを生成できないため、Shortcuts実機確認用IPAはGitHub ActionsのmacOS／Xcode 26.6経路で生成する。現在の`AddCounterValueIntent`と`AppbaseShortcuts`が実例である。

## 検証

変更後は次を分けて確認する。

1. WSLの`swift test`でfeature処理、ID衝突、独立保存を確認する。
2. `xtool dev build --ipa`でiOSフレームワークを含むコンパイル、Widget組込み、IPAのZIP整合性を確認する。
3. App Intentを含む場合はGitHub Actionsで公式メタデータ入りIPAを生成する。
4. SideStoreで更新インストールし、一覧からの起動、保存値の独立、通知許可の拒否、通知予約、foregroundと終了状態からの通知タップを実機で確認する。

ビルド成功、SideStore導入成功、各system surfaceの動作成功は別々の証拠として記録する。
