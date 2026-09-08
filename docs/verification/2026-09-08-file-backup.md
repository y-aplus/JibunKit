# ファイル単位バックアップの接続と検証

## 確認済みの土台

CI [34190686473](https://github.com/y-aplus/JibunKit/actions/runs/34190686473)、source `f23311b90235400a1c95bcddbe2b2b597351fa70` は成功。Recordsのsnapshot復元、参照添付の欠落時の保存維持、独立iOSビルド、生成Feature組込みビルド、通常IPA検証を実行した。このrunではSimulator UIテストは指定していない。直近のUI回帰成功は34189152345。

## 今回の接続点

`MiniAppFileBackupProvider`は、Featureが所有するsnapshotディレクトリとschemaを受け渡す任意の契約。添付を共通のData/Base64配列へ変換しない。既存のJSON providerとその読込みは変更しない。ファイルproviderは新規保存先にだけ書き出し、ディレクトリ以外やsymlinkをsnapshotとして返さない。

復元は既存の`MiniAppRestorePlan`の順次適用と途中失敗報告を共用する。選択した全providerのprepareが成功してから適用可能になる。prepareはライブ保存値を変更せず、Featureのschemaと内容を検証する責任を持つ。選択外の内容はprepareしない。独立Feature間のrollbackは保証しない。

snapshotの寿命と不変性は呼出側の責任。確認画面の表示中から適用完了まで保持し、終了後に作業ファイルを片付ける。書き出し途中の失敗で残ったファイルは成功したバックアップとして扱わない。

## 追加テスト（CI結果待ち）

- 実ファイルの書き出し、schema保持、既存保存先への上書き拒否。
- 通常ファイルをsnapshotディレクトリとして返すproviderの拒否。
- 全選択対象の事前検証失敗時に保存値を変更しないこと、選択外の不正内容からの独立性。
- 途中失敗の完了済みID・失敗IDと後続の停止、重複ID・未知選択の拒否。

## 残る作業

Recordsのprepare/apply adapter、持ち運び形式、共通画面のファイル入出力と寿命管理、旧JSONの読込み共存、大容量メモリ計測、schema移行は未完了。新しい接続点だけをV3の完成とはしない。Recordsは引き続きCore非依存で、接続はIntegration層に置く。
