# 管理画面の削除失敗・再試行fixture

`P0BManagementFailureProbe`は、通常IPAには含めず、署名済み診断hostへだけコピーする管理画面fixtureである。通常の`MiniAppDefinition`にlifetime、removal、onUnregisterを登録し、管理共通層を迂回する専用削除ボタンは持たない。

fixtureの保存層は独自ownerとUserDefaults suiteを渡した`CounterStore`である。`onUnregister`はprocess内の初回だけ意図的に失敗し、その時点の保存値を診断メッセージへ含める。登録解除が失敗するためremoval callbackはまだ呼ばれず、管理状態は「削除が未完了」のままになる。二回目は登録解除が成功し、同じ管理画面の「削除を再試行」から所有キーだけを削除する。

UITestは次の操作列を一つの実画面試験で確認する。

1. 通常Counterの値を増やして比較値を保存する。
2. 診断Featureへ登録済みURLで入り、独自ownerの値を増やす。
3. 管理画面で対象名とデータ説明を確認して削除する。
4. 登録解除段階の失敗、未完了状態、エラー内の未削除保存値を確認する。
5. 削除を再試行して完了させ、初期状態で再登録する。
6. 診断Featureが0へ戻り、通常Counterの値が変わらないことを確認する。

長いlazy listでは、行がまだaccessibility treeに存在しない場合がある。試験は上下へbounded scrollして対象行をmaterializeし、単純な`waitForExistence`だけに依存しない。失敗注入はこのfixture内だけに閉じ、productionの登録解除や保存処理へ分岐を加えない。
