# Pacchi. Part 3 接続手順

## 現在の状態

このリポジトリの開始時点にはFirebase SDK・ログイン・友達・メッセージ・カメラ・音楽のコードがありませんでした。既存のガラケーUI・メモ・音を保ち、端末だけで使う機能と、接続後に使う機能を実装しています。Firebaseへのデプロイや実ユーザーへの送信は行っていません。

| 端末だけで使える | バックエンドへの接続後に使える |
| --- | --- |
| メモ/写真/ひとこまからシール作成、切り抜き、形、キャプション | 最初の会話/写真、記念日、任意提供の誕生日の自動シール |
| 配置、ドラッグ、拡大縮小、回転、重なり順、削除、思い出表示 | 承認した友達の電話訪問、ギフト送受信・受け取り |
| 手紙の本文・封筒・切手・音の下書き、プレビュー | Special Mailの送受信・開封、写真つきDaily Moment送信 |
| 日替わりのお題、文字・写真の保存、スキップ、履歴 | 公開範囲を検証した装飾共有、ブロック |

未接続の状態では送信済み・受信済み・友達を作りません。メニューから接続説明が表示されます。通知は受信箱/友達の更新時と接続時の取得に対応し、APNsによるバックグラウンド通知は未実装です。予約配信はUIに出さず、サーバーも予約時刻つきのリクエストを拒否します。

## 1. 既存データとの対応づけ

`backend/functions/.env.example` を `.env.<FirebaseプロジェクトID>` として設定します。値は既存アプリのコレクション名です。新しいusers/friendsシステムを作るための設定ではありません。現在のアプリに認証・友達機能がまだないため、実運用前にその接続元を用意する必要があります。

参照アダプターは `backend/functions/index.js` の `existing` / `accepted` / `contacts` です。既存のフィールドや構造が違う場合、この層を対応させます。

| 既存データ | アダプターが読み取る項目 |
| --- | --- |
| friendships | `members: [uidA, uidB]`, `status: "accepted"`, `acceptedAt: Timestamp`（記念日用） |
| users | `displayName`。任意で `birthday: { month, day, shareWithFriends: true }` |
| blocks | 文書IDは `policy.js` の `key(blockerUID, blockedUID)`。`blockerId`, `blockedId` |
| messages | `senderId`, `recipientId`, `kind: "text" / "photo"`, `delivered: true` |

メッセージの `delivered` と送信者情報は、既存の信頼できる配信処理で検証・確定される必要があります。クライアントが自由に送信者や配信済みフラグを変更できるデータを、このトリガーに接続しないでください。既存ブロックのID規則が異なる場合は、`blockRefs` と `pacchiBlock` の両方を合わせます。

既存friendshipsに複合インデックスが必要な場合は `members ARRAY_CONTAINS + status ASCENDING` を既存インデックスへ追加してください。`backend/firestore.indexes.json` は新設の受信箱2種のインデックスのみです。

## 2. サーバーを準備

Node.js 22で `backend/functions` の `npm ci`、`npm test`、`npm run check` を実行します。依存はlockfileに固定しています。Functions、Firestore、App Check、Schedulerを使用できるFirebaseプロジェクトが必要です。

`backend/firebase.json` は統合用テンプレートです。既存アプリがある場合、そのfirebase.json・Security Rules・インデックスへマージしてください。提供したRulesファイルだけで既存のルールを置き換えると、既存機能のアクセスが拒否されます。逆に、既存のワイルドカードの広いallowルールが新しい名前空間に一致するとdenyを回避するため、その点も点検してください。

Pacchiの新しい名前空間は以下です。クライアントの直接読み書きを拒否し、認証・App Checkを要求するCallable経由だけにしています。Admin SDKはRulesを通らないため、各ハンドラーでも所有者・宛先・友達関係を検証します。

- `pacchiPrivate/{uid}/stickers/{id}`：所有者の記念シール。会話本文は保存しません。
- `pacchiGifts/{id}`：ギフト。リクエストIDとトランザクションで重複防止。
- `pacchiMail/{id}`：宛先を限定した手紙。
- `pacchiMomentPhotos/{id}`：Daily Momentの私的なJPEG添付。宛先検証後のCallableだけで取得。
- `pacchiPhones/{uid}`：明示選択された公式ギフト素材のみの共有用データ。

同じギフトの再受け取りは同じシールIDになり、同じ初回イベントは所有者・友達・種別の決定的なIDになります。記念日と誕生日のIDには年も含みます。カレンダー処理は日本時間の毎朝9:15、誕生日は `shareWithFriends == true` の場合のみ動きます。頻度や連続利用日数は使いません。

共有画面の公開範囲は「設定案」です。「この設定で共有を更新」の成功後にサーバーへ反映されます。飾りの配置変更も再度共有更新が必要です。

`pacchiSendMoment` は私的な写真を最大200KBのJPEGとして保存します。クライアントで480px以内に再エンコードして位置情報を除去します。共有は相手・日付・内容からIDを決め、同じ内容の通信再試行は重複しません。内容を変えて送る場合は新しい手紙になります。公開プロフィールには添付も本文も入りません。写真共有はFirestore内に限定し、Storageの新規公開URLは発行しません。

## 3. iOSの既存セッションを渡す

`ContentView(backend:)` / `RetroPhoneView(store:backend:)` が注入ポイントです。`FriendshipBackend` を既存サービスで実装するか、`FirebaseFriendshipBackend` を使います。SDK依存は自動追加していません。

`FirebaseFriendshipBackend` の引数は以下です。

- `ownerId`：Firebase Authの現在のUID。
- `baseURL`：`https://asia-northeast1-<project-id>.cloudfunctions.net`。
- `credential`：既存のログインセッションから毎回取得する `FirebaseSessionCredential(ownerId:idToken:)`。UIDが変わっていないことも検証してください。
- `appCheckToken`：既存のApp Checkから取得する新しいトークン。

トークンをソースコードやUserDefaultsに書かないでください。ログアウト/アカウント切替時はルートを `.id(currentUID)` で作り直すか、保持しているNavigationManagerに `setBackend` を渡します。離脱/切替時は進行中の通信をキャンセルし、他アカウントのシール・受信内容は表示しません。端末で作ったシールとメモはアカウントに属さない「端末内」のデータです。

受信箱の取得はギフト/手紙100件、シール500件までです。古い受信箱のページ送りと大量データの管理画面はこの版には含めていません。アカウント削除時は既存サービスからPacchiの新規名前空間も削除してください。

## 4. 接続後の実機・エミュレーター確認

1. 2つのテストアカウントで友達を承認し、両方の端末で「友達を更新」を実行。
2. 最初の配信済みメッセージ/写真で各記念シールが1枚だけ生成され、同じイベントを再配信しても増えないことを確認。
3. アプリ再起動後にシールが残り、シールを押すとストーリーが出ることを確認。公開データに本文が含まれないことも確認。
4. ギフトの送信/受け取りを同じIDで同時実行し、ギフト1件・シール1枚だけになることを確認。
5. 「非公開」で訪問拒否、友達公開＋飾り選択＋共有更新で選んだ飾りだけ表示されることを確認。
6. 他ユーザーのUID、手紙ID、写真IDでアクセスして拒否されること、片方向のブロックでも送信/訪問/添付取得が拒否されることを確認。
7. 手紙の封筒・切手・音・本文、写真つきDaily Momentが宛先だけに届き、開封できることを確認。
8. App Checkなし・期限切れIDトークン・Rulesを通る直接書き込みを拒否することをFirebase Emulator/実機で確認。
9. 記念日・任意公開の誕生日・未公開の誕生日・年をまたいだ再実行を検証。

ローカルのサーバーテストは実ハンドラー＋メモリDBアダプターを使います。エミュレーター、IAM、デプロイ、実際のApp Check、配信トリガー、端末間通信を検証済みという意味ではありません。

参考：[Callableの認証プロトコル](https://firebase.google.com/docs/functions/callable-reference)、[Firestoreトランザクション](https://firebase.google.com/docs/firestore/manage-data/transactions)、[Rulesとサーバークライアント](https://firebase.google.com/docs/firestore/security/get-started)。
