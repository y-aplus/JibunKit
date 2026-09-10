# D13 通知requestの所有Feature配送

状態: このrequest配送単位は実装・CI検証済み。

source `c11bcaf`の[34528052611](https://github.com/y-aplus/JibunKit/actions/runs/34528052611)は全工程success。native requestの3unitと共有155試験（0失敗）、署名付きhostのforeground二owner/custom action配送試験（133.529秒）が成功した。通常host検索/起動回帰40.574秒、Records編集/永続化70.775秒、独立Feature/template・app/widget/IPAも通過。Records添付試験には既知のQuick Look expected failureが含まれ、previewの新規成功証拠には含めない。

既存配送はkind/requestIdentifier/destination/userTextだけを渡しており、独立アプリがnative delegateから取得できた通知content・独自payload・triggerを失っていた。`MiniAppNotificationRequestSnapshot`をactionとforegroundイベントへ追加し、通常hostの両delegate経路から接続する。native secure codingを使い、独自userInfo schemaやunchecked Sendableを設けない。

検証内容:

- 実UNNotificationRequestのtitle/subtitle/body/category/thread/badge、ネストしたuserInfo、Data、繰返しtriggerをsecure archive経由で復元する。snapshotのexecutor間受渡しもSwift 6で検査する。
- 元の可変dictionaryを変えてもsnapshotが変わらず、読み出しごとのnative objectが独立する。
- action handlerへ所有者だけのsnapshotとuserTextを渡し、custom actionで画面を変更しない。
- 既存の署名付きhost通知試験にnative requestの検査を組込み、foreground A/Bそれぞれのowner/recordとcustom actionのowner/record/title/bodyを復元できた場合だけ受信済みにする。通常delegateを通らない直接resolver呼出しを証拠にしない。

選択UI testは`MigrationUITests/GeneratedFeatureUITests/testNativeNotificationRequestPayloadsReachOnlyTheirOwners`。既存のforeground試験→所有通知削除→custom action試験を一単位にし、後者でB表示維持とAのみの受信を確認する。

添付ファイルの保持/コピー、実APNs配送、response.targetScene、受信日時はこの単位の検証対象外。native requestに添付参照があってもファイル寿命を延長する保証はない。D13全体を完了とはしない。
