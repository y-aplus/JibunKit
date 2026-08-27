# スーパーアプリ基盤 0.1 技術確認

確認日: 2026-08-28

**確認範囲: 設計、Apple・提供元の一次資料、公開ソースの読解。ビルド・ツールの実行・SideStore導入・実機動作は未検証。技術的な成立を確認済みとはしない。**

対象の完成条件は[0.1の設計](2026-08-28-appbaseios-foundation-design.md)のF1〜F7・O1〜O4。この確認で必須条件の削除・延期は行わない。ユーザーに技術の正しさを保証してもらうものでもない。

## 1. 利用者への影響と結論

| 確認箇所 | 現時点の判断 | 利用者への影響 |
| --- | --- | --- |
| ミニアプリを1本にまとめる構成 | ホストと各ミニアプリを分ける設計は維持。内部の分割方法は実装で確認する。 | 複数画面を持つミニアプリも対象。ただし独立アプリのような権限・障害の隔離はない。 |
| Windows上のWSLでのビルド | xtoolに手順とWidget対応例がある。今回の構成で動くことは未確認。 | ローカル優先は維持する。Mac購入は必要条件にしない。 |
| ショートカットへの独自操作の登録 | ローカルのメタデータ生成経路が未実証。優先して確認する。 | IPAができても、ショートカットに操作が現れなければF2は未達。 |
| SideStore再署名後のWidgetとのデータ共有 | 共有領域の識別子の変更を考慮する必要がある。優先して確認する。 | Widgetだけ値が見えない問題を防ぐため、本体とWidgetを実機で組み合わせて確認する。 |
| 保存・通知・更新 | 基本方式は維持。保存の競合、起動時の通知処理、更新後の識別子の扱いを具体化する。 | 更新で値や操作の入口が失われないことを0.1で確認する。 |

最大の未解決点は「ローカルでショートカット登録まで成立するか」と「無料アカウント・SideStore再署名後も本体とWidgetがデータを共有できるか」。クラウド上のmacOS環境は前者の代替経路になり得るが、署名後の権限や共有領域の問題まで解決するとは限らない。

## 2. ビルドとApp Intents

### 一次資料・ソースで確認したこと

- xtoolの手順はWindows上のWSLを対象に含む。現行手順はLinux用Swift 6.3とXcode 26からのSDK準備を説明している。Xcodeの取得はAppleへのログインと利用条件の確認が必要。[導入手順](https://github.com/xtool-org/xtool/blob/2d58d987edff728fccebc6df643b1672e3583f00/Documentation/xtool.docc/Installation-Linux.md)
- Widgetは別のビルド対象として作成する例がある。これはSideStoreでの署名・共有領域の動作実証ではない。[拡張の手順](https://github.com/xtool-org/xtool/blob/2d58d987edff728fccebc6df643b1672e3583f00/Documentation/xtool.docc/Appex.md)
- `xtool dev build`のソースではIPA出力とAppleアカウントを使う署名が別オプションになっている。ビルド経路では`--sign`を付けた場合に認証を要求する。権限情報を付けるためのアドホック署名とは区別する。SDK準備まで含めて認証不要と判断したものではない。[ビルド処理](https://github.com/xtool-org/xtool/blob/2d58d987edff728fccebc6df643b1672e3583f00/Sources/XToolSupport/DevCommand.swift)
- App Intents対応の[Issue #145](https://github.com/xtool-org/xtool/issues/145)は未解決。[PR #217](https://github.com/xtool-org/xtool/pull/217)は閉じられているが未マージであることをAPIでも確認した。
- 代替の[re-appintentsmetadataprocessor](https://codeberg.org/viraptor/re-appintentsmetadataprocessor/src/commit/074d2f640773a35e4f25e0b19aa2658163f9e8ec/README.md)はSwiftソースとコンパイラの定数出力からメタデータを生成する。READMEの例はmacOS向け。iOS、xtoolとの接続、SideStoreでの登録・入出力が成立する証拠にはしない。READMEのMIT表記と実際に取り込む配布物の条件も採用時に確認する。
- Appleの現行APIでは`supportedModes`がiOS 26から利用可能。`openAppWhenRun`はiOS 26で非推奨になっている。0.1で許容済みの「アプリ画面が開く実行」は、使用するSDK・最低対応OSに合うAPIで実装する。最新資料にある別の新APIまで無条件に使わない。[実行モード](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)、[旧プロパティ](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun)

### 実装で確認すること

App Intentは具体的な型として宣言し、数値入力・戻り値とメタデータ生成を確認する。ミニアプリ一覧への登録だけでショートカットも自動登録されるとはしない。共通の更新処理を呼び、起動直後にも保存先や依存先が準備されることを確認する。[Appleの実装・テスト手順](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent)

まずホストに宣言を集める現在の方針を維持し、メタデータを複数モジュールから集約する難しさを不用意に増やさない。具体的な配置は実証で決める。

IPAをSideStoreで導入する経路を優先し、xtoolからのUSB直接導入を必須にしない。Appleの認証情報や個人の署名鍵をGitHubのビルド環境へ送る前提にはしない。GitHub Actionsへ切り替える場合も、同じソース・必須機能・実機条件を検証する。

## 3. SideStoreとWidgetの共有領域

### SideStore 0.6.3のソースで確認したこと

調査対象はタグ`0.6.3`が指すコミット`4deda9229c6746234f1ace7df16eb9af9e19f3fd`。

1. 署名準備時にApp Group識別子へチーム識別子を追加する処理がある。[署名用プロファイルの準備](https://github.com/SideStore/SideStore/blob/4deda9229c6746234f1ace7df16eb9af9e19f3fd/AltStore/Operations/FetchProvisioningProfilesOperation.swift)
2. 再署名時、プロファイル内のApp Group識別子を各バンドルのInfo.plistへ書き込む。[再署名処理](https://github.com/SideStore/SideStore/blob/4deda9229c6746234f1ace7df16eb9af9e19f3fd/AltStore/Operations/ResignAppOperation.swift)
3. この情報のキーは`ALTAppGroups`で、SideStore自身にもそれを読む処理がある。[Bundleの補助処理](https://github.com/SideStore/SideStore/blob/4deda9229c6746234f1ace7df16eb9af9e19f3fd/Shared/Extensions/Bundle%2BAltStore.swift)

したがって、ビルド前のApp Group名だけをコードに固定して読めばよいとは判断できない。`ALTAppGroups`はSideStore側の実装であり、Appleの標準APIや将来の不変契約としては扱わない。

### 設計への反映

- 本体とWidgetが使う共有領域の識別子を解決する処理を1か所にまとめる。再署名後の情報から、意図した共有領域を双方が選べることを確認する。候補の先頭を無条件に使わない。
- 共有領域が見つからない場合に、別のローカル保存先へ黙って切り替えて正常に見せない。検証上の失敗として判別できるようにする。
- 同じAppleアカウント・同じアプリ識別子での通常の更新・署名更新をまず検証する。アカウント変更、識別子変更、アンインストールと再導入でもデータが残ると拡張解釈しない。別途移行・復元の対象として説明する。
- 0.1では本体が更新を担当し、Widgetは表示用の値を読む。OSが表示更新を管理するため、更新要求と実際の表示を分けて検証する。[Appleの共有領域の説明](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[Widget更新](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

提供元には2026-08-20付の[共有領域を読めないという報告 #1437](https://github.com/SideStore/SideStore/issues/1437)もある。ただし利用者の報告で、原因は確定しておらず、記載バージョンも今回の0.6.3とは一致しない。この報告を根拠に今回も必ず失敗すると断定しない。

## 4. 保存・通知・ミニアプリの境界

以下は設計レビュー上の実装注意点。動作検証済みという意味ではない。

- **保存の競合:** 画面からの更新とショートカットからの更新を同じ処理に通す。読み書きを直列化し、同時実行で更新が消えないことを確認する。同じプロセス内の制御と、Widgetを含むプロセス間の共有を混同しない。
- **通知からの起動:** 通知の受け取り口はホストが管理し、ミニアプリIDと行き先を渡す。終了状態からの起動でも画面の準備後に遷移できるようにする。通知許可の拒否、未登録の行き先も扱う。通知の受け取り口は起動完了前に設定する。[Appleの通知処理](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html)
- **登録の衝突:** ミニアプリID・保存先・通知ID・起動先の重複を、登録の検査やテストで見つける。フォルダ名を分けるだけでは十分としない。
- **隔離の限界:** 同じアプリに組み込むミニアプリ同士には、独立したOSの権限境界はない。1つのミニアプリのクラッシュが全体に影響し得る。未確認の第三者コードを安全に実行する場所とは説明しない。
- **テストの実行場所:** SwiftUI等のiOS依存部分と、入力・更新・保存形式などの処理を分ける。WSLで実行できるテストと、iOS向けビルド・実機でしか確認できないものを分け、未実行部分を合格扱いにしない。
- **配布物の一致:** クラウドを使う場合でも、ソースの版、ツール、SDK、アプリ識別子、生成IPAを追跡する。IPAのビルド成功とSideStoreでの導入成功は別に記録する。

### 継続して使える構成かの確認

0.1の実装レビューでは、カウンター専用の処理がホストへ入り込んでいないか、第2ミニアプリが同じ追加方法を使えるか、保存・更新の境界を壊さずに育てられるかを確認する。これは既存のF1・F5・F6を支える設計確認であり、新たな製品機能の追加ではない。

1.0で単純破棄することが分かっている0.1専用の構成を採らない。一方、将来候補のIPAアダプタ・変換器を理由に、未使用の拡張口や変換基盤を先行実装しない。実際の問題で構成変更が必要になった場合に、理由と移行方法を説明できることを重視する。[継続性とYAGNIの設計原則](2026-08-28-appbaseios-1.0-direction.md)

## 5. 実装開始後の確認順

1. ツール・SDKの版と正規の取得方法を固定し、最小アプリを作成する。
2. WSL経由でのApp Intentの登録・数値入力・結果返却を確かめる。既存ツールと薄い接続処理の範囲で成立しなければ理由を記録し、合意済みのクラウド経路へ進む。
3. 無料アカウントとSideStoreによる本体・Widgetの導入と共有領域の読取りを確かめる。署名後の識別子とアプリ枠・App IDの消費を記録する。[SideStoreの制限](https://docs.sidestore.io/docs/faq)
4. 保存、通知、第2ミニアプリ、更新・署名更新後の継続動作をF1〜F7に照合する。
5. GitHub公開・文書・検証記録・リリース成果物をO1〜O4に照合する。

2・3で失敗しても、ショートカットやWidgetを後の版へ移して0.1を完成扱いにはしない。許容範囲を超えるツール内部の改造や生成メタデータの手修正は中断し、機能への影響と選択肢を示す。
