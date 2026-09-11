# Native Cookie保持と終了時点の比較

状態: 比較診断はCI検証済み。過去の欠落原因は未解決。製品の永続化保証を変更しない。

34537802126では、native setCookie完了・読戻し成功後に背景化してアプリを終了したが、再起動後は識別子付きprofileと比較用default storeの両方でCookieがmissingだった。二ownerとも同じ結果で、JibunKit固有の識別子だけを原因とは決められない。

## 今回の実験

`WebStorageOwnershipUITests/testNativeCookiePersistenceMatchesDefaultAtControlledTerminationIntervals`で背景化の確認からterminateまでの間隔を0・5・15秒に固定して比較する。二ownerを各条件で実行し、各回の新しいUUID値をprofile/defaultへ保存する。保存直後は両方の値が一致することを必須にし、再起動後の両値をログへ残す。以前の試行で保存された値を今回の成功と誤認しない。

これは終了時点を変える比較実験であり、待機秒数を製品へ追加する対処ではない。既存の`testWebDataPersistsAndClearingPreservesOtherFeature`は保持を要求するまま変更しない。新診断の成功はprofileとdefaultの結果一致を意味し、両方missingでも永続化成功を意味しない。識別子付きだけmissingなら比較は失敗する。各intervalで一回ずつの観測で、再現頻度や必要待機時間の保証にはしない。

同一アプリ内のdefault storeとの比較であり、別プロセスの独立アプリとの比較やHTTP応答のSet-Cookie試験ではない。ページは従来fixtureのloadHTMLStringを使用する。製品コードと通常IPAには変更なし。

## 仕様と実装を区別する

[AppleのsetCookie API](https://developer.apple.com/documentation/webkit/wkhttpcookiestore/setcookie(_:completionhandler:))と[公開WebKitのWKHTTPCookieStore実装](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKHTTPCookieStore.mm)を再確認した。公開実装ではsetCookieとprivateなdisk flushは別の入口である。これだけでSimulatorの失敗原因や公開APIの永続化時点は確定しない。非公開flushをJibunKitから呼ばず、実際のOS結果と独立に扱う。

## 結果

[34544099154](https://github.com/y-aplus/JibunKit/actions/runs/34544099154)、source `094c71408e4fdfc645dc30f91557838572cc8b39` は成功。比較UI試験は274.114秒。各行のexpected/profile/baselineは、その試行で生成したUUID付き値と完全一致した。

| 背景化確認後の待機 | owner A | owner B |
| --- | --- | --- |
| 0秒 | profile/defaultとも今回値を保持 | profile/defaultとも今回値を保持 |
| 5秒 | profile/defaultとも今回値を保持 | profile/defaultとも今回値を保持 |
| 15秒 | profile/defaultとも今回値を保持 | profile/defaultとも今回値を保持 |

今回の観測には欠落も識別子付き固有の差もなかった。0秒条件でも保持されたので、「数秒待てば解決する」という結論や製品側の待機追加には進まない。以前の全件実行との差（先行試験、process/OS状態など）の切分けは残る。

共有167試験、独立Feature、native build/IPA、通常host検索の限定回帰46.091秒も成功。Recordsの2試験は既知のSimulator Quick Look expected failureを含む成功165.214秒。通常host全件、Files往復、既存の厳格Cookie保持試験はこのrunでは実行していない。
