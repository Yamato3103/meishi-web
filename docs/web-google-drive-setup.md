# Google Drive 連携のセットアップ(Web 版)

MeishiVault Web で **Google Drive** 同期を使うには、あなた自身の Google Cloud プロジェクトに
**OAuth 2.0 クライアント ID(ウェブアプリケーション)** を1つ作り、そのクライアント ID をアプリに
設定します。アプリは `drive.file` スコープだけを要求するため、**Drive 全体は見えず、アプリが
作成したファイルのみ**を読み書きします(§6.1)。Google の年次審査(CASA)も不要です。

> 設定しなくてもアプリは完全に動きます(ローカルのみで名刺管理できます)。Drive 同期は任意です。
> iOS 版の設定は [google-drive-setup.md](google-drive-setup.md) を参照。**両者は同じ `MeishiVault/`
> フォルダ・同じ `card.json` フォーマットを共有**するため、iOS と Web で同じ名刺を相互同期できます。

---

## 1. Google Cloud プロジェクトと OAuth 同意画面

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成(既存でも可)。
2. **API とサービス → ライブラリ** で「Google Drive API」を有効化。
3. **API とサービス → OAuth 同意画面**:
   - User Type: **External**(個人利用ならテストユーザーに自分を追加すれば審査不要)。
   - アプリ名・サポートメール等を入力。
   - **スコープ**に `.../auth/drive.file` を追加。
   - **テストユーザー**に自分の Google アカウントを追加。

## 2. ウェブアプリ用 OAuth クライアント ID を作成

1. **API とサービス → 認証情報 → 認証情報を作成 → OAuth クライアント ID**。
2. アプリケーションの種類: **ウェブアプリケーション**。
3. **承認済みの JavaScript 生成元** に、アプリを配信するオリジンを追加:
   - 開発: `http://localhost:5173`(Vite の既定ポート。実際に使うポートに合わせる)
   - 本番: `https://<あなたのドメイン>`
4. 作成すると **クライアント ID** が発行される。形式:

   ```
   1234567890-abcdefg.apps.googleusercontent.com
   ```

   > Web(GIS トークンモデル)では **クライアントシークレットは使いません**。リダイレクト URI の
   > 登録も不要です(JavaScript 生成元だけでよい)。

## 3. アプリに設定する

環境変数(Vite の `import.meta.env`)でクライアント ID を渡します。`web/.env.local` に:

```
VITE_GOOGLE_CLIENT_ID=1234567890-abcdefg.apps.googleusercontent.com
```

設定画面の「同期」節は、この値があるときだけ **Google Drive** を表示します(P3-E part3 で結線予定)。

## 4. 使い方(結線後)

1. **設定 → 同期** を開く。
2. **「Google Drive に接続」** を押すと、Google Identity Services のトークン取得ポップアップが開く。
3. `drive.file` を許可すると「接続済み」になり、**「今すぐ同期」** でマイドライブ直下の
   **`MeishiVault`** フォルダに `<id>.json` が同期されます(iOS 版と同じフォルダ)。

---

## 仕組み(実装メモ)

| 項目 | 内容 |
|---|---|
| スコープ | `https://www.googleapis.com/auth/drive.file` のみ |
| 認可方式 | **Google Identity Services(GIS)トークンモデル**(`google.accounts.oauth2.initTokenClient`)。アクセストークン(約1時間)を都度取得。ブラウザ SPA にリフレッシュトークンは発行されないため、失効時は再取得する |
| トークン保管 | メモリのみ(`CallbackTokenProvider` がアプリ提供の取得関数をラップし、期限の60秒前までキャッシュ) |
| 保存先 | マイドライブ直下 `MeishiVault/`(`drive.file` のため自動作成・フォルダ選択 UI なし) |
| 楽観ロック | ファイルの `version` を用いた check-then-act(競合は名刺単位に局所化) |
| 実装 | `web/src/sync/googleDriveRemoteStore.ts`(REST)/ `web/src/sync/driveHttp.ts`(HTTP 抽象 + トークンプロバイダ) |

### トークンプロバイダの結線例(GIS)

`GoogleDriveRemoteStore` は「有効なトークンをくれる何か」(`DriveTokenProvider`)だけに依存します。
GIS を使う場合は、取得コールバックを `CallbackTokenProvider` に渡します:

```ts
import { CallbackTokenProvider, GoogleDriveRemoteStore } from './sync';

// GIS スクリプト(https://accounts.google.com/gsi/client)を index.html で読み込んでおく。
const tokenClient = google.accounts.oauth2.initTokenClient({
  client_id: import.meta.env.VITE_GOOGLE_CLIENT_ID,
  scope: 'https://www.googleapis.com/auth/drive.file',
  callback: () => {}, // 下の Promise 側で受ける
});

const tokens = new CallbackTokenProvider(() => new Promise((resolve, reject) => {
  tokenClient.callback = (resp) => {
    if (resp.error) reject(new Error(resp.error));
    else resolve({ token: resp.access_token, expiresAt: Date.now() + resp.expires_in * 1000 });
  };
  tokenClient.requestAccessToken();
}));

const remote = new GoogleDriveRemoteStore({ tokens });
```

## トラブルシューティング

- **ポップアップが出ない / すぐ閉じる** → **承認済みの JavaScript 生成元**に、いま開いているオリジン
  (プロトコル + ホスト + ポート)が正確に登録されているか確認。
- **`access_denied`** → OAuth 同意画面の「テストユーザー」に自分のアカウントを追加したか確認。
- **`403 / insufficient scopes`** → 同意画面と `initTokenClient` の scope が `drive.file` になっているか確認。
- **一定時間で 401** → アクセストークンの失効。再度「今すぐ同期」でトークンを取り直す(仕様)。
