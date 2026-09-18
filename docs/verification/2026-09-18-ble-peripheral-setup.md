# AndroidをBLE試験用の相手機器にする準備

まだ実施依頼ではありません。候補IPAが合格してから、iPhoneまたはiPadと手元のAndroidで行う手順です。無線動作とmacroの実機UIは未確認です。

## Androidで最初に用意するもの

nRF Connect for Androidの「Configure GATT Server」で、[設定値一覧](../../Tests/Fixtures/ble-peripheral/README.md)の専用serviceと2 characteristicを登録します。

- service: `ad539a02-1289-44dc-bd27-f991c68a1fb9`
- Read/Write: `9e0f4195-64b6-4c4a-8ffa-e8dd8f4036d5`。READ + WRITE、openの読書きpermission。
- Read/Notify: `0b1ec4d4-1383-4460-b1e2-9ae98653cc1b`。READ + NOTIFY。CCCDの存在も確認。

[通知macro](../../Tests/Fixtures/ble-peripheral/JibunKit-P2S-notify.xml)をimportします。これは公式macro形式との照合とXML構文確認までで、Android上でのimport/実行成功ではありません。GATT設定XMLの公開schemaは確認できないため、そのファイルは推測で作っていません。

Advertiserでconnectableな広告を開始し、service UUIDと名前`JibunKit-P2S-5276`を載せます。広告が31 bytesに収まらなければ、名前をscan responseへ移すか短くし、service UUIDを優先します。AndroidはBLE advertising対応が必要で、Bluetoothと要求されたNearby devices許可を有効にします。

## 接続後の確認

現在のJibunKitの「スキャン」は全scanです。Service UUID欄を入力してもscan filterにはなりません。

1. JibunKitから広告名で自分のAndroidを選んで接続します。まだWriteは押しません。
2. Androidでimport済みmacroを開始します。最初にRead/Write値を`01 02`へ設定し、Readを待ちます。接続後の画面でmacroを起動できない場合は、そのUI条件を確認してから進め、未接続の状態で起動できるとは仮定しません。
3. JibunKitで「全Service検索」。上記serviceが見つかったら、その「Service候補」を押してService UUID欄へ選択します。
4. Read/Write UUIDをCharacteristic欄へ入れ、「指定Characteristic検索」→「Read」。結果が`01 02`になったことを確認します。
5. Read/Notify UUIDへ切替え、「指定Characteristic検索」→「Subscribe」。「購読中」を確認します。
6. Read/Write UUIDへ戻し、送信hexを`03 04`にして「Write with response」。Androidのmacroが値を照合し、通知`05 06`を送ります。
7. Write成功と、Notify欄に`05 06`が出たことを確認します。エラーならその段階で止め、連打しません。

名前・UUID・初期値の照合は試験相手の取り違え防止であり、認証ではありません。一般の心拍計等にこの値を書き込む手順ではありません。iBeaconは別の方式で、このGATT試験の成功だけでは確認済みになりません。

## Primary references

- [Nordic nRF Connect documentation: Advertiser and Configure GATT Server](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/documentation/README.md)
- [Nordic macro XML grammar: server read/write, set-value, and send-notification](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/documentation/Macros/README.md)
- [Nordic macro XML example using hexadecimal bytes](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/Thingy52%20sample%20macros/macros/Blinky.xml)
- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android BluetoothLeAdvertiser API and 31-byte legacy limit](https://developer.android.com/reference/android/bluetooth/le/BluetoothLeAdvertiser)
- [Android BluetoothAdapter advertising capability check](https://developer.android.com/reference/android/bluetooth/BluetoothAdapter)
