# P2-C: 撮影・音声の所有と中断復帰

2026-09-16開始。公開0.8.2後のbaselineは52a29ff。対象はP2-1（AudioSession/Now Playing）とP2-2（撮影/文書・コードscan）。次の実機確認のまとまりで0.8.xを進める。P2-Lの実装/非実機/対象別OS証拠を再利用できるが、Live Bの単発差分とP2-5 partialは取り消さない。この差分に依存しない撮影/音声の設計は並行して進める。

## 共通責任と作業分担

Featureはplayer/recorder/capture session、native構成と業務データを所有する。JibunKitは一つのプロセスへ統合して失われる所有者別の受付・調停・取消・解放・配送を補う。すべてを一つの固定playerやcapture画面へ移植させず、AVFoundation/VisionKit/MediaPlayerの標準型と構成の自由度を保つ。

既存MiniAppID、MiniAppFeatureLifetime/Runtime、MiniAppPresentationOwner、scene activity、permissions/Feature consentを使う。新規APIはoptionalとし、既存Counter/Reminderの振舞いを変えない。OS許可はapp全体であり、Feature単位の利用同意・利用受付と区別する。

- 音声: AudioSessionのプロセス共有構成、互換要求の共存、非互換要求の理由付き競合/明示切替、停止の完了待ち、OS中断/経路変更/復帰を扱う。無条件全排他やcategory setterだけで完成としない。Now Playingは標準MPNowPlayingSessionが適合する範囲を使い、操作対象と停止後の配送を分離する。ユーザー停止を復帰イベントで勝手に再開しない。
- 撮影: 可視性/scene/Feature停止とnative captureの寿命を接続する。cameraとmicrophone等の要求資源を区別し、片側の取消で別Featureの処理を止めない。対応端末・OSの制約とJibunKit未実装を区別する。写真・文書scan・code scanの通常経路を含める。
- 共有接点: 音声付き撮影はAudioSession調停を迂回しない。ただし設計段階で互いの未確定APIを作り込まない。native SDK objectのactor跨ぎを避け、factory/callbackのisolationを型に残す。Swift6 compile未確認を隠さない。

親は共通契約、必要なhost/Definition/lifecycle接点、Package/Project/CI/Tools、統合と出荷を所有する。音声担当はSources/JibunKitCore/Audio/、Tests/JibunKitCoreTests/Audio/、Tests/MediaAudio/、docs/guides/audio.md。撮影担当はSources/JibunKitCore/Capture/、Tests/JibunKitCoreTests/Capture/、Tests/MediaCapture/、docs/guides/capture.md。初回はそれぞれ専用の設計提案文書だけを提出し、親が共通接点を一度揃えてから実装を並列依頼する。子はCIを実行しない。

## 検証境界

初回予算は計画済み3run以内。個別APIや担当ごとにCIを出さず、両担当の実装・試験・fixture・契約を一括レビューした後に統合境界を固定する。正確な入力/filter・実行レーン・再利用証拠・30分以内の所要見込みは実装が揃ってから投入前に確定する。3回失敗以内に原因を切り分ける。

自動試験は互換/非互換要求、片側取消・失敗、古いcallback拒否、解放順序、再開条件、他ownerの非初期値/世代保持を担当する。モデル試験に加えて実Feature接続を代表構成で検査し、同じ管理/バックアップ機構の全組合せを実機へ戻さない。

実機は新しいOS動作に限定する。音声は実録音/再生、背景・OS中断/経路変更、Now Playing操作配送の代表例。撮影は許可・実camera/scan・取消と解放、Feature切替時の代表的な資源保持。各ケースの必要性と観測方法をfixture実装時に確定し、モバイルで判定できないstatus表示を放置しない。版番号/試験/docだけの変更で成功済み実機を繰り返さない。

## 初回設計提出の完了条件

Apple一次資料と現在のSDK宣言を確認し、最小の公開API候補（Swift宣言）、actor/SDK所有、状態遷移、既存hostとの接点、失敗/競合時の振舞い、2Featureの具体例、自動/実機の分担を1文書にまとめる。要求していない機能を複雑さだけで除外しない。実装が必要なOS差分と、独立アプリでも受ける制約を分ける。未確定の共通接点は相手レーンへ要求として列挙し、共有ファイルやCIを変更しない。設計文書をcommitしたら終了し、監視やpollをせず親への一回の完了通知で引き渡す。
