# Google Drive 連携のセットアップ

MeishiVault の「同期」で **Google Drive** を選ぶには、あなた自身の Google Cloud プロジェクトに
OAuth クライアントを1つ作り、そのクライアント ID をアプリに設定します。アプリは
`drive.file` スコープだけを要求するため、**Drive 全体は見えず、アプリが作成したファイルのみ**を
読み書きします(§6.1)。Google の年次審査(CASA)も不要です。

> 設定しなくてもアプリは完全に動きます。Google Drive を使わない場合は「フォルダ同期」
> (端末内 / iCloud Drive フォルダ)をそのままお使いください。

---

## 1. Google Cloud プロジェクトと OAuth 同意画面

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成(既存でも可)。
2. **API とサービス → ライブラリ** で「Google Drive API」を有効化。
3. **API とサービス → OAuth 同意画面**:
   - User Type: **External**(個人利用ならテストユーザーに自分を追加すれば審査不要)。
   - アプリ名・サポートメール等を入力。
   - **スコープ**に `.../auth/drive.file` を追加。
   - **テストユーザー**に自分の Google アカウントを追加。

## 2. iOS 用 OAuth クライアント ID を作成

1. **API とサービス → 認証情報 → 認証情報を作成 → OAuth クライアント ID**。
2. アプリケーションの種類: **iOS**。
3. **バンドル ID**: `com.meishivault.app`(アプリの Bundle Identifier と一致させる)。
4. 作成すると **クライアント ID** が発行される。形式:

   ```
   1234567890-abcdefg.apps.googleusercontent.com
   ```

5. iOS クライアントの **リダイレクト URI スキーム**は、クライアント ID を逆順にしたもの:

   ```
   com.googleusercontent.apps.1234567890-abcdefg
   ```

## 3. アプリに設定する

**もう Info.plist の枠は用意してある。** `ios/MeishiVault/Info.plist` が
プロジェクトに配線済み(`INFOPLIST_FILE = Info.plist;`、`GENERATE_INFOPLIST_FILE = YES`
と併用してカメラ/連絡先などの自動生成キーはマージされる)。**あなたは値を3か所埋めるだけ**。
空のままなら Drive 同期は非表示のまま(フォルダ同期は動く)。

### 3-1. ClientID / RedirectScheme を埋める

`ios/MeishiVault/Info.plist` の `GoogleDriveOAuth`(既に空の枠がある)を埋める:

```xml
<key>GoogleDriveOAuth</key>
<dict>
    <key>ClientID</key>
    <string>1234567890-abcdefg.apps.googleusercontent.com</string>
    <key>RedirectScheme</key>
    <string>com.googleusercontent.apps.1234567890-abcdefg</string>
</dict>
```

### 3-2. URL スキームを実IDに置き換える

同じファイルの `CFBundleURLTypes` にプレースホルダのスキームが入っている。
`com.googleusercontent.apps.YOUR-CLIENT-ID` を **3-1 の RedirectScheme と完全一致**する値に置き換える:

```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>com.googleusercontent.apps.1234567890-abcdefg</string>
</array>
```

> ※ `UIFileSharingEnabled`(Files アプリ可視化)も同じ `ios/MeishiVault/Info.plist` にある。
> `INFOPLIST_KEY_UIFileSharingEnabled` は Xcode の生成plistでは無視される(実測)ため、
> この鍵だけは Info.plist に直接置いてある。触らなくてよい。

## 4. 使い方

1. アプリを再ビルドして起動。
2. **設定 → 同期** を開く(`GoogleDriveOAuth` が設定されていれば「保存先」に **Google Drive** が現れます)。
3. 保存先で **Google Drive** を選び、**「Google Drive に接続」** をタップ。
4. Google のサインイン画面(`ASWebAuthenticationSession`)で許可すると「接続済み」になります。
5. **「今すぐ同期」** で、マイドライブ直下に作られる **`MeishiVault`** フォルダに
   `<id>.json` と画像が同期されます。

---

## 仕組み(実装メモ)

| 項目 | 内容 |
|---|---|
| スコープ | `https://www.googleapis.com/auth/drive.file` のみ |
| 認可方式 | Authorization Code + **PKCE**(クライアントシークレット不要) |
| トークン保管 | アクセストークン=メモリ / リフレッシュトークン=**Keychain** |
| 保存先 | マイドライブ直下 `MeishiVault/`(`drive.file` のため自動作成・フォルダ選択 UI なし) |
| 楽観ロック | ファイルの `version` を用いた check-then-act(競合は名刺単位に局所化) |
| 実装 | `MeishiKit/Sync/GoogleDriveRemoteStore.swift`(REST)/ `MeishiVault/App/GoogleDriveAuth.swift`(OAuth) |

## トラブルシューティング

- **「保存先」に Google Drive が出ない** → `Info.plist` の `GoogleDriveOAuth`(ClientID / RedirectScheme)が
  正しく入っているか確認。
- **接続後すぐサインイン画面が閉じる / エラー** → `CFBundleURLTypes` のスキームが RedirectScheme と
  完全一致しているか、バンドル ID が Cloud Console の iOS クライアントと一致しているか確認。
- **`access_denied`** → OAuth 同意画面の「テストユーザー」に自分のアカウントを追加したか確認。
- **`invalid_grant`(更新失敗)** → 一度「切断」して再接続(リフレッシュトークンの再取得)。
