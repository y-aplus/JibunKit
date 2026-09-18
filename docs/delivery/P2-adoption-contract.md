# P2-6 採用範囲と検証境界

2026-09-18。Issue #6の推奨境界に従い、既存成果で成立する通常範囲を採用する。需要が低そうだから未検証を除外する判断ではない。全体はpartial、現在の公開版は0.8.3。

## 採用する範囲

| 対象 | 既存成果と追加作業 | 合格証拠の区別 |
| --- | --- | --- |
| idle timer | Feature/操作leaseと選択scene scopeを再利用。通常Definition/lifetimeから要求を保持し、非選択・backgroundで実効要求を外す診断を追加 | 既存34366651143/34367286197/34497999557のsource別所有試験とiOS property読戻しを再利用。実際の自動消灯/ロックは実機のみ |
| 外観 | SwiftUI environment、presentationへ伝播するpreferredColorScheme、包含UIKit controllerのoverrideUserInterfaceStyleを別々に検証 | 通常rootでA→B→A、sheetと他windowの保持を実trait/環境値で確認。非接続UIWindowや固定sleepだけで成立を判定しない |
| Spotlight | owner別index/domain、選択itemの登録ownerへの配送、片側削除を採用 | 34509301964/34523416261のnative index/query/実OS検索/cold launchをsource差分付きで再利用。実機は関連管理シナリオへまとめる |
| Widget翻訳 | 標準en/ja resourceで通常Counter Widget本文/状態/gallery文言を表示。独自resource合成は追加しない | 実built appexのキー/value読戻しと、OSによるgallery/home描画を別々に記録。appへWidget専用文字列を混入させない |
| 権限用途説明 | 採用P2が必要とする実UsageDescriptionを既存target別/locale別helperで合成 | 辞書合成・実bundleと、OS dialogの実言語表示を区別。通知等へ架空のUsageDescriptionを追加しない |

## 境界の説明

任意のUIAppearance proxyやapp/window singletonを書き換えた既存コードを自動的に隔離できるとは主張しない。これは単一processに統合した結果の差分で、OSの必然的制約と取り違えず、Feature-localなUIKit包含/View環境への接続方法を提供する。既存APIを不必要に狭めず、必要なnative構成は専用adapterで接続できる余地を残す。preferredColorSchemeを単なるview-local設定とは説明しない。

Spotlightの一般NSUserActivity/search query continuationや任意multiwindow配送、textContentのquery readbackは既存の選択item配送と別の残件として台帳に残す。他の必須P2機能がこれらを必要とする場合は、P2-6で採らなかったことだけを理由に省略しない。Widget任意extensionの一般化や全OS権限の万能調停も今回の検証内容とは別。

## 実装とCIの分担

2本の既存Sol lowプロジェクトスレッドが外観/idle fixtureとWidget/用途説明を担当。親がProject、通常host生成、built bundle検査、採否/証拠を統合する。worker別CIは行わない。41c97f1のAR/Action初回CIは実行中のまま固定し、この追加分は次の一括検証候補へ含める。まだ実行していない試験結果を成功として扱わない。

実機に委ねるのは自動消灯、代表権限dialog、実OSのWidget/Spotlight入口。Coreのrace、字句一致、生成物の配置は自動試験へ寄せる。採用権限を全種類×全言語で人手反復する手順にはしない。
