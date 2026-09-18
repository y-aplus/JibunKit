# 0.8.5後のOS配送検証準備

公開0.8.5の後続作業。変更は診断fixture/試験/runnerに限定し、通常製品を変更しない。ユーザーは「次に実機確認が発生したところでしばらく停止」と予告済み。今回の位置/HTTP差分を一括レビュー・CI・IPA取得まで進め、実機手順を提示した時点で全スレッドを停止し、再開指示を待つ。

## 位置: 前景geofenceの実OS callback

worker1519d0cを統合。XCUILocationによる外側→内側→外側の移動で、regions ownerの実enter/exit delegateと新規永続記録を確認する。単なる登録やrequestStateは成功条件ではない。開始時に同localIDを置換し、別owner・旧ログ・保存失敗は通知成功にしない。

親レビューで初期座標のsubstring `37.33` が内側37.3349も許容する不足を修正。外側を37.3280、中心37.3349/-122.0090、半径300mにし、双方の地点を境界から十分離す。enter/exit各35秒で打ち切り、配送時刻の製品保証ではない。Appleの[地域監視の説明](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html)では境界のcushionを超える必要があり、登録だけではenterは発生しない。現行Simulatorでの成立は未検証。実電波iBeaconやcold起動の成功と混同しない。

## HTTP: 診断専用のprocess終了と相関

background URLSessionのSimulator上の自動再起動を製品の合否ゲートにしない。Apple DTSの[背景実行のテスト説明](https://developer.apple.com/forums/thread/685525)とbackground session資料は、ユーザーforce quitと診断用exitを区別している。通常IPAへ終了ボタンを入れない。

既存HTTP診断へ論理run ID、起点process/task、保存成功とcompletion実呼出しの相関を補い、普通の同process・再要求・混在を新process復元として扱わない変更をworkerへ依頼済み。通信URLやpayload自体を記録しない。通信先や外部サービスを新規追加せず既存URL入力を使う。サーバのrequest回数1はOS再試行まで排除するため必須条件にしない。

既存の実機転送先はhttpbingoのdrip（10秒/10bytes）で、同processの背景callbackから保存/completionが確認済み。この過去結果をprocess終了後の成功と読み替えない。新診断の具体的な実機手順は統合・ビルド後に提示する。継続処理code1の追究は再開しない。

## 一括CIの準備

native合格後、Release/署名/IPA CRCを先に検証し、最後にOS UIを実行する順へ変更。OS UI失敗時も検査済み診断IPAをartifactに残すが、result.passed=false/CI失敗を維持する。単にIPAを得るためだけの再ビルドを避ける。新しい位置試験はOS UI計6件に含まれ、名前ごとの成功/skipなし判定は維持する。

位置/runnerのローカル13試験・py_compile・diff検査成功。HTTP差分提出後にnative件数・全差分・CI時間上限を確認して一回にまとめる。現在の追加実機操作なし。

## HTTP提出の統合レビュー

worker6134cde/be77b19を統合。保存失敗時の成功表示、破損ファイルの上書き、通常完了後の再試行不能、生成済み未開始taskの放置、全ファイル一括hashを修正してからCIへ進める。親で保存processを別記録し「旧processで保存・新processで完了だけ」を拒否する試験と、エラー終了後のhost completion返却を記録して再試行を許す試験も追加した。finish()のBool=trueを実completion呼出し条件にする。

表示は明確に「OSの起動契機は未判定」とし、手動再入場を自動起動の証明にしない。過去の保存済み転送証拠を表示するボタンを追加し、ユーザーが開くまでにprocessが再び終了していても診断結果を読める。通常IPAに含まれないfixtureのみ。公開0.8.5へ変更を加えていない。

既存httpbingo drip URLをこのPCから再確認し、HTTP200/10bytes/12.107秒。これは実機のcold転送成功ではなく、診断用通信先の応答確認だけ。ローカル35試験・py_compile・diff検査成功。一括CIのOS UIは6件、nativeはsourceから抽出した全件合格を要求。前回15分52秒にgeofenceの最大95秒と追加nativeを加え、準備/upload込み25分以内を想定する。

## CI35364846699の切り分け

a317524はコンパイル成功、nativeの既存HTTP admission/cleanup試験1件が失敗。転送runを生成しないfake delegate fixtureが、新しいcold chain表示を要求していたことが原因。保存表示の存在と、既存の永続観測による保存→host completion返却順、実completion counterを確認し、cold成功を主張しないassertへ修正する。新しい証拠相関/保存失敗/再試行試験は成功。native段階の失敗なので今回のRelease/OS UIは未実行。製品障害やgeofence不成立とは判断しない。この境界の初失敗として原因を確認後に再投入する。

## CI35365770330成功・停止境界

4a1340ab3cedfe10fded79fa975d4a4bd65d160cはnative87件/OS UI6件成功、失敗0/skip0。geofenceの実enter/exit callback試験も58.701秒で成功。Release/IPAの署名/CRC検査成功。ダウンロードしたstructured summaryとIPAを照合した。新しいHTTP診断の実機結果はまだない。

[診断IPA・再開時手順](2026-09-19-background-http-device.md)を準備。ユーザー予告に従い提示後は全スレッドの実装・新CIを停止し、再開指示を待つ。公開0.8.5/mainは維持し、この診断変更を未検証のまま正式版へ追加しない。
