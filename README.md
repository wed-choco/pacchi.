# Pacchi. — Phase 1

新しい起動画面は、SwiftUIの図形とグラデーションで描くピンクの折りたたみ電話です。画面またはOKを押すと5項目のメニューが開き、数字1〜5でも選択できます。My Phone / Friends / Memories / Profileのタブ、実時刻、キーの触覚、任意の効果音、Reduce Motion対応を追加しました。Profileの音設定は端末内に保存されます。

- Xcodeで `pacchi..xcodeproj` を開き、`pacchi.` スキームを実行。Swift 6、iOS 17以上。
- 新しいホーム: `pacchi./PacchiHome.swift`。ナビゲーションと触覚: `pacchi./PacchiHomeModel.swift`。
- Messages / Memories / Camera / Decorateの案内から既存の電話ツールに進めます。既存の保存形式は変更していません。
- FriendsはPhase 1の案内画面です。新しいサンプル会話・訪問は未実装。SwiftDataへの移行と新しいカスタマイズ機能はPhase 2以降で実装します。
- 検証: Xcode 27.1、Swift 6、arm64 iOS SimulatorでDebugビルド成功。iOS 27シミュレータで起動とホーム表示を確認。実機の触覚・消音スイッチ、VoiceOver、iOS 17実行時の操作確認は未実施。

```sh
xcodebuild -project 'pacchi..xcodeproj' -scheme 'pacchi.' -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/pacchi-phase1-build CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
```

以下は従来の電話ツールの説明です。

# pacchi.

SwiftUIで動く、ピンクのストレート型ガラケー。Xcodeで `pacchi..xcodeproj` を開き、`pacchi.` ターゲットを実行してください。既存の本体・アンテナ・液晶サイズと色・物理キー・メモ・効果音を維持しています。

## カメラ・アルバム

メニュー12「カメラ」、13「しゃしんアルバム」を追加。液晶内で撮影・フィルター・日付・保存・再加工・お気に入り・シール作成を操作できます。旧データの移行、変更ファイル、Xcode設定、実機テスト手順は **[CAMERA_ALBUM.md](CAMERA_ALBUM.md)** を参照してください。

## Part 3

- **Memory Stickers**：写真、保存済みメモ、最新のDaily Momentからシールを作成。ハート/ほし/まる/リボン/しかく、写真の切り抜き、キャプション、端末内保存。タップすると作成日とストーリーを液晶に表示。
- **飾りつけ**：本体の下部に配置。十字キーで位置、サイズ、回転を変更。配置中はドラッグ・ピンチ・回転も可能。重なり順、はがす、削除に対応。
- **Special Mail**：本文・封筒・切手・通知音の下書き保存、液晶プレビュー。接続すると友達への送信・受信・開封に対応。
- **Daily Little Moment**：日替わりで任意のお題。文字と写真、端末内保存、履歴、スキップ。接続すると選んだ友達に写真つきの手紙として共有。
- **Friendship**：接続後の自動記念シール、Phone Visit、公式素材のギフト、受信箱、共有範囲、ブロックのクライアントとサーバーコード。

Firebase・友達・メッセージ・カメラ・音楽は開始時点で未実装でした。この版ではPhotosPickerから写真を取り込みます。今回は液晶内の撮影・アルバム・再加工・シール連携を追加しました。音楽再生は未実装です。未接続で送信や訪問が動作したようには表示しません。設定方法と実運用前の確認は **[BACKEND_SETUP.md](BACKEND_SETUP.md)** を参照してください。予約送信とAPNs通知は未実装です。

## 操作

- 左ソフトキー / OK：選択、決定。入力中の意味は液晶左下に表示。
- 十字キー：メニュー選択。11項目のメニューは5項目ずつ表示。長いストーリーは←→でページ送り。
- 右ソフトキー：戻る。文字入力中は1文字削除。空欄なら前の画面へ。
- 通話キー：メニュー / 終話キー：待受。
- 数字1〜9、0：リストの1〜10番を選択。メニューの#は次ページ（11番は十字キーで選択）。待受の#は音設定。
- 入力：2〜9の短い連打で英字を切替。0は空白、1は句読点、#は文字確定、*は削除。同じキーの次の文字は0.8秒待つか#で確定。
- 写真の切り抜き：十字キーで位置、2/8で拡大縮小、OKで確定。
- シール配置：OKまたは#で「位置→サイズ→回転」を切替、右キーで終了。

入力は英数字・句読点です。日本語はUI表示に対応しています。写真の選択だけはOS標準ピッカーを使用し、それ以外の画面は既存の小さな液晶内に表示します。

## 保存とプライバシー

メモ（60文字・1件）と音設定は従来のUserDefaultsを使用。新しいシール・私的な思い出・手紙の下書き（240文字）・Daily MomentはApplication Support/PacchiにJSONを原子的に保存し、写真は位置情報を除去したJPEGとして保存します。iOSのファイル保護を使用。読めない保存ファイルは上書きしません。

写真やメモから作ったシールは共有用のデータに含めません。Phone Visitには明示選択した公式ギフト素材と配置だけを渡します。Daily Momentの写真共有は、宛先と友達関係をサーバーで検証します。記念シールには会話本文を自動保存しません。

効果音はAVFoundationで生成した電子音。iOSのambientカテゴリーで消音スイッチに従い、設定からOFFにできます。LCDフォントは日本語対応のシステム等幅フォントです。

## 変更ファイル

| ファイル | 内容 |
| --- | --- |
| `pacchi./ContentView.swift` | 既存本体へのシールレイヤー、LCDと写真選択、四方向操作の接続 |
| `pacchi./PhoneNavigationManager.swift` | 既存ナビゲーションを拡張した状態・キー操作・保存/通信処理 |
| `pacchi./MemoryModels.swift` | シール、ギフト、プロフィール、手紙、ひとこまのデータモデル |
| `pacchi./MemoryStore.swift` | JSON保存、写真の取り込みと切り抜き、重複防止、削除 |
| `pacchi./StickerViews.swift` | コードで描くシール、配置ジェスチャー、封筒、訪問先の電話 |
| `pacchi./PhoneScreenContent.swift` | LCD内の一覧・入力・ストーリー・プレビュー |
| `pacchi./FriendshipBackend.swift` | 既存セッション注入用のプロトコル、Firebase Callable接続 |
| `backend/` | Functions、ルール統合用テンプレート、インデックス、12件のサーバーテスト |
| `Tests/MemoryFeatureChecks.swift` | 保存・復元・操作・切り抜き・壊れたファイルの保護のチェック |

## 端末内で試すチェックリスト

- [ ] 従来のメモ保存、着信音、音ON/OFFを確認。
- [ ] メニュー6「思い出シール」から保存メモを選び、形とひとことを決めて保存。
- [ ] ストーリーの「操作」から貼る、位置/サイズ/回転、手前にする、はがすを試す。
- [ ] アプリ再起動後もシールと配置が残り、本体のシールを押すと思い出が開くことを確認。
- [ ] 写真を選び、十字キーと2/8で切り抜いて保存。ピッカーのキャンセルや読み込めない写真も確認。
- [ ] シール削除後に再起動し、削除が保持されることを確認。
- [ ] 手紙の本文・封筒・切手・音を設定し、プレビューと再起動後の下書き復元を確認。
- [ ] Daily Momentで文字/写真を残し、同日に再保存して履歴が増殖しないこと、スキップで催促されないことを確認。
- [ ] 未接続の友達/受信箱/送信では設定説明が出て、架空の友達や送信済み表示が出ないことを確認。
- [ ] 小さいiPhone/横向き、VoiceOver、視差効果を減らす設定、実機の消音スイッチを確認。

Swiftのチェックはアプリソース（MyApp.swiftを除く）と `Tests/MemoryFeatureChecks.swift` を `swiftc -parse-as-library -swift-version 5 -default-isolation MainActor` で実行できます。サーバーはNode 22で `cd backend/functions` → `npm ci` → `npm test`。テスト用の架空データはアプリには同梱していません。
# pacchi.
# pacchi.
# pacchi.
