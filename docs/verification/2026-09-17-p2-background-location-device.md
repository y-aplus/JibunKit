# P2-B 背景処理・位置情報の実機確認（修正版の起動確認待ち）

## 現在確認する修正版

対象は`3af8e32532e2fb2b1759920da7a716a00639de10`、0.8.3/build13。[CI35180204806](https://github.com/y-aplus/JibunKit/actions/runs/35180204806)で共有393件（既存Keychain2skip）、独立Records11件、通常検索UI、背景/位置native19件（skipなし）と通常/診断IPAが成功。通常11分52秒・診断8分52秒。再署名ID対応、Aの起動登録失敗後もBを登録できること、部分登録の重複実行を避けること、有効化/復元で失敗ownerの開始禁止を迂回しないことを自動検証した。

[修正版診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-P2-B-3af8e32.ipa) ／ [修正版診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-P2-B-3af8e32.zip)

[同sourceの通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-normal-3af8e32.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-normal-3af8e32.zip)

**今回は削除せず修正版を上書きし、アプリ一覧まで開くかだけ確認する。** 一覧に「準備失敗」が出ればその文言を報告する。継続処理・位置更新の旧手順は起動確認後に再開し、成功していない項目を既済にしない。

修正版IPAで3bundleの既存ID/0.8.3/build13、追加したbuild時ID metadata、診断5scheduler/3background modes、通常版の診断非混入、CRC/署名resourceと一重ZIPを照合済み。公開GETは公開後に記録する。実機再署名後の起動成功はまだ受領していない。

## 旧候補で確認した起動不具合

**以下のda62672診断版は実機で起動直後に終了したため、確認を中断する。再試行不要。** 添付クラッシュ記録のapp binary UUIDが配布IPAと一致し、main threadの`NotificationAppDelegate.application(_:didFinishLaunchingWithOptions:)`で`EXC_BREAKPOINT/SIGTRAP`を確認。元のthrowされたエラー文は記録になく、SideStoreの許可ID書換え→旧ID登録拒否はコードからの有力な推定である。端末識別子やログ全文はリポジトリへ保存しない。復旧用には[安定版0.8.3 IPA](https://github.com/y-aplus/JibunKit/releases/download/0.8.3/JibunKit.ipa)を削除せず上書きできる。

修正では実行時の許可リストに一致する再署名後IDへnative register/submit/cancelを統一し、Feature起動登録の失敗を全appのtrapに変えず、当該ownerの開始拒否と画面表示へ変える。修正版CIは成功。実機の起動確認は未実施。以下は旧候補の手順と証拠として保持する。

対象sourceは`da6267213a15872f3eb3860157edf0840e866bd2`、0.8.3/build13。[CI35176070341](https://github.com/y-aplus/JibunKit/actions/runs/35176070341)で通常版と背景/位置native17件・診断版が成功。正式0.8.4の出荷確認ではない。実機で確認した成果のまとまりを次の版へ進める。

[診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-P2-B-da62672.ipa) ／ [診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-P2-B-da62672.zip)

[戻す通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-normal-da62672.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-normal-da62672.zip)

アプリを削除せず上書きする。ZIP内は同名IPA一つ。異常時はその画面の文言と直前の操作を伝え、その項目の反復は不要。会話では一まとまりずつ案内し、返答ごとのcommit/pushや全管理・復元マトリクスの反復は行わない。

## 最初に確認する継続処理

「Background A」→「継続処理を開始」。開始できれば進捗が0から増える。ロック画面でも継続処理の表示が出て進むか確認する。

60秒で終わる前にロック画面側で取消できれば一回取り消し、アプリへ戻ってAが停止したことを確認する。表示や取消操作が見つからない、または「受付失敗」なら、その文言を報告する。「受付済み」だけではOSが実行した証拠にしない。

その後「Background B」で開始し、今度は取消せず完了を待つ。アプリ画面で「進捗60/60」「成果1」になることを確認する。OS都合で開始されない場合、時間を決めずに待ち続けない。

## 継続処理の次に確認する位置更新

管理画面で「位置更新Probe」の位置情報を「許可」にする。「位置更新Probe」→「When In Use許可を要求」でiOSの使用中許可を与え、「前景位置更新」で緯度・経度が表示されることを確認する。座標そのものを報告する必要はない。

「背景位置更新」を押し、ホーム画面へ出て少し歩いた後に戻る。event数や位置が更新されたか確認し、最後に「位置更新停止」。屋内・静止中に更新がないことだけでは不具合と判定しない。こちらは必要になった段階で会話から案内する。

## まだ完了にしない項目

- refresh/processing/shared refreshの受付と、OSが後から選ぶ実起動・期限は別。画面の受付表示や注入callback成功を実OS起動へ読み替えない。
- 実HTTP転送のA取消/B保存は今回のSimulatorで成功。OSが終了したappを再起動して配送するcold再接続は未確認。アプリスイッチャーで強制終了する操作を、OS終了と同一に扱わない。外部HTTPの準備とcoldイベントを読み取る診断が必要であり、今は手元の任意URL入力を依頼しない。
- geofenceの実進退・再起動後配送、iBeaconの実電波配送は未確認。iBeacon送信機材の有無を別途確認する。現診断はUUID `E2C56DB5-DFFB-48D2-B060-D0F5A71096E0`、major1/minor1。機材がない場合は自動配送試験の成功で実測済みにしない。
- Regionのcold callbackはアプリ画面を開く際の状態表示に上書きされる可能性がある。現在の画面文言だけでcold配送時刻を断定せず、必要な観測を整えてから依頼する。
- これらの残件があるため、最初の継続処理・位置更新が成功してもP2-3/P2-4全体をcompleteへ変更しない。

## 自動試験と出荷物の証拠

source `da62672`で共有389件（既存Keychain2skip/失敗0）、独立Records11件、通常検索UI、背景10件・位置7件のnative試験（skip/失敗0）が成功。通常job14分13秒、診断job7分24秒。所有/管理/復元/世代/期限/失敗/B保持、実HTTP A取消・Bファイル保存、実CoreLocation設定とSDK値を対象とする。OS schedulerの起動や物理移動は注入試験から推定しない。

IPA全entry CRC、app/Widget/Shareの既存IDと0.8.3/build13、署名resource、診断構成の5scheduler宣言と3background modes、通常版の診断非混入を照合。各ZIP内IPAの一致を検査した。新規prerelease `p2-b-device-check-20260917`を同sourceへ固定して公開。診断/通常のIPA/ZIP計4assetを無認証で再取得し、SHA-256・CRCとZIP内IPA一致を確認済み。既存tag/assetは差し替えていない。

受領した実機結果は起動直後終了のみ。継続処理・位置の各操作には到達していない。修正版の起動と対象操作を確認してから更新する。
