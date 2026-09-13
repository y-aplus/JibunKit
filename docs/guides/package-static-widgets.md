# Swift Package所有の静的Widget接続

このガイドは、通常の`MiniAppDefinition`と共有storeを持つFeatureが、静的Widgetを既存hostへ出荷するためのP1接続を示す。設定可能・操作可能WidgetとControlはP2であり、この手順の対象外とする。

## Feature package

Feature ID、Widget `kind`、保存namespaceは一度公開した後に変更しない。`kind`はFeature IDとは別の、extension内で一意な逆DNS文字列にする。表示名と説明はpackage resourceの`Localizable.strings`から読み、hostの翻訳へ暗黙に依存させない。

Featureは通常画面と同じIDの`MiniAppDefinition`を公開し、同じ`MiniAppFeatureLifetime`と`MiniAppRemovalProvider`を渡す。Widgetが読む値は`MiniAppContext.storageKey(_:)`でowner prefixを付け、appとextensionの両targetに同じ`JibunKitAppGroup`とApp Group entitlementを設定する。hostからの通常の読み書きは共有`MiniAppRestoreCoordinator.withStoreAccess(for:)`を通す。削除callbackは管理層がownerを予約した後に呼ばれるため、所有keyだけを冪等に削除する。

Widget processは`MiniAppManagement.savedStatus(for:defaults:)`で同じ共有defaultsの状態を読み、`.enabled`以外では所有値を表示しない。この読取りは別processの操作予約ではない。書込み入口はhost側の通常管理・保存調停を迂回してはならない。状態変更後の`WidgetCenter.reloadAllTimelines()`は更新要求であり、実際の描画成功や即時更新を保証しない。

## Hostとextension

通常hostは列挙したDefinitionから既存の`MiniAppManagement.Registration`を作る。`lifetime`、`removal`、`onUnregister`をそのまま接続し、管理状態もFeature値も同じApp Group defaultsを使う。無効化は値を保持し、削除は対象ownerの値だけを消し、再有効化は受付を戻すだけで業務処理や値の作成を自動開始しない。

静的Widgetを通常出荷するには、Widget型をSwift Package製品に含めるだけでは足りない。出荷対象appが埋め込むWidget extensionの`@main WidgetBundle`へ各Widget型を明示的に列挙し、extension targetから各package製品へ依存する。二Featureを一つの標準Widget extensionへ登録でき、FeatureごとのextensionやCore wrapper、生成器は必須ではない。単独A、単独B、統合hostの登録集合を比較し、統合集合が二つの安定kindの和であることを検査する。

## 受入試験

`Tests/PackageWidgets`は同一suiteへA=11/B=22を保存し、次を確認する。

- packageの通常Definition、lifetime、removalが同じowner IDである。
- A更新後もB=22を保持する。
- A無効化中はA値を隠し、通常store書込みを拒否し、Bを保持する。
- A再有効化で削除前のA値を再表示する。
- A削除後もB値を保持し、A再登録後の新しい値がBへ影響しない。
- 英語・日本語resourceと安定kindがpackageに含まれる。
- 単独A/Bと統合hostをWidget galleryで発見し、previewとホーム画面を画像/OCRで実描画確認する。統合hostでは更新・無効化・再有効化・削除・再登録の各状態を同じホーム画面上のA/Bで確認する。

timeline取得、extension build、kindのbinary文字列、reload要求の成功だけをOS描画成功として扱わない。

## 0.8候補で予約する端末確認

P1実装時には端末合格にしない。0.8.0候補IPAで、通常のインストール/更新後にgalleryへ二Widgetが翻訳済み表示名で現れること、ホームへ追加したA/Bが共有値を描画すること、アプリでAを更新・無効化・再有効化・削除・再登録した各段階でAだけが変化しBが残ること、アプリ再起動後にも管理状態と値が保持されることを一括確認する。reload要求と実表示の時差も記録し、候補の1.0境界をこの確認から独自に確定しない。
