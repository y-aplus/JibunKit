# Feature間のbackground refresh共有枠

状態: 実装予定の契約。0.5.0には含まれず、D15の完了証拠ではない。

## 失われる境界

独立appならA/Bがそれぞれ持つrefresh要求枠は、一つのhostへ統合すると共有になる。
現在の`MiniAppBackgroundTaskCenter`はnative identifierの登録・取消・実行寿命を所有者別に
制限するが、要求はそのままnative schedulerへ送る。二Featureのrefreshを保持する調停はない。

Appleの[submit仕様](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:))では、
pending上限はrefresh 1件/processing 10件。同じ未実行要求の再提出は置換になる。
[earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)は
実行可能時刻の下限であり、期限や正確な起動時刻ではない。2026-09-11に仕様を再確認した。
OS枠や実行時間を増やすことは保証せず、枠を共有したために要求が消える差分を補う。

## 次の実装単位

既存のnative identifierを直接扱うAPIを暗黙に置換せず、明示的なhost共有refresh経路を追加する。
最初の対象はapp refreshのみ。通信/給電条件が異なるprocessingを同じ一枠へ潰さない。

- hostは一つの許可済みnative refresh IDを起動時に登録する。Featureは安定owner/local IDで
  論理要求とhandlerを登録し、OS IDの奪い合いを避ける。画面生成を登録条件にしない。
- 各ownerは複数local IDを持てる。同一owner/local IDの再要求だけが前のpending要求を置換する。
  異なるowner/local IDの日時・要求内容は保持する。
- pending要求はhost所有の永続journalへ保存し、最も早い下限日時をnative要求へ反映する。
  永続化前に受付成功を返さない。native受付とjournal保存は一つのtransactionにはならないため、
  「論理要求を保存済み」と「OSへ提出済み」を結果として区別する。OS失敗を成功へ偽装せず、
  保存済み要求は起動時や明示再調停で再提出できるようにする。
- 起動時はjournalを読み、owner handlerの登録を終えてから再調停する。破損journalを空扱いして
  他Featureの要求を消さない。未登録ownerの要求も他ownerへ配送せず、未解決として保持する。
- OS launch時に、その時点で下限日時に達した要求の世代を固定する。未来の要求は実行しない。
  実行中に同じIDへ再要求された新世代は、古い実行の完了・取消では消さない。
- 受付済みの期限到達要求を先着ownerだけで消費しない。各要求へ独立した論理executionを渡し、
  協調的な非同期処理を開始できるようにする。FeatureがMainActorを占有するハングの隔離は別問題。
- native taskの完了権はhost batchだけが持つ。全論理executionの完了/cleanupを待って一度だけ
  native completionを呼ぶ。Feature一つの完了で他FeatureのOS実行時間を終わらせない。
- OS期限通知はそのbatchの未完了executionだけに一度配送する。期限通知と処理終了を区別し、
  handler解除後も完了までexecutionを保持する。再入・重複completionで新batchを消さない。
- pending取消は当該owner/local IDのみ。A取消後もBをjournalに保持し、Bの下限日時で再調停する。
  pending取消は実行中処理の完了を意味しない。既存の他native IDを勝手にcancelしない。
- 配送前にin-flight世代を永続化する。プロセス終了で完了記録がない世代は次回の復旧対象とし、
  消失を避ける代わりに再配送の可能性を明示する。Feature側の更新処理は同じ要求世代への
  再実行を扱う必要がある。プロセス終了をまたいだexactly-once実行は保証しない。

通常のdirect refresh登録が既にOS一枠を使用している場合は、その要求を消さずnative拒否を返す。
共有経路を使うFeatureを明示的に接続する責任はhostにあり、全てのBGTaskScheduler利用を
実行時にinterceptする機構は追加しない。

## 一続きで必要な検証

1. 容量1を強制するschedulerでA/Bを受理し、OS pendingは一つ、論理pendingは両方を保持。
   A/Bの日時逆転・同じlocal ID・Aだけの取消・native提出失敗からの再調停を確認する。
2. journalを新しいcenterへ読み直し、owner/日時/世代を維持。破損・保存失敗・未登録ownerで
   要求を消さず、失敗を明示する。保存とOS受付の間で終了した場合も復旧する。
3. 期限到達したA/Bへ配送し、未来のCは保留。A完了後もBの実行を保持し、全完了でnativeを
   一度だけ終了。期限切れ・重複完了・handler解除・再入・実行中の同一ID再要求を組み合わせる。
4. in-flight記録を残して新process相当で復旧し、未完了世代だけを再配送可能にする。
   すでに完了した世代と、実行中に追加した新世代を混同しない。
5. iOSで永続journalの再読込と二Feature handler配送を確認する。注入launchはOS配送証拠と
   分ける。実機でnative pending一枠と取消後の他owner保持を比較し、実OS launch/期限配送は
   別に記録する。Simulatorのnative拒否をwrapper成功で隠さない。

永続化・batch寿命・native接続を別々の完成品とは数えない。これらが接続されるまで共有枠の
補完は未完。OSが許可しない起動を独自timerやprivate APIで代替しない。
