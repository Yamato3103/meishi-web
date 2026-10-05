import { CallbackTokenProvider } from '../sync';
import type { DriveTokenProvider } from '../sync';

/**
 * Google Identity Services(GIS)トークンモデルでアクセストークンを取得する。
 *
 * ブラウザ SPA にはリフレッシュトークンが発行されないため、失効時は再取得する。
 * クライアント ID は `VITE_GOOGLE_CLIENT_ID` で渡す(docs/web-google-drive-setup.md)。
 * 実サインインの疎通は各自の Google Cloud 設定が必要。
 */
const GIS_SRC = 'https://accounts.google.com/gsi/client';
const SCOPE = 'https://www.googleapis.com/auth/drive.file';

interface TokenResponse { access_token: string; expires_in?: number; error?: string }
/** ポップアップを閉じた等、`callback` が呼ばれずに終わるケースを拾う(GIS 公式サポート)。 */
interface TokenClientError { type: string; message?: string }
interface TokenClient {
  callback: (resp: TokenResponse) => void;
  error_callback: (error: TokenClientError) => void;
  requestAccessToken: () => void;
}
interface GisGlobal {
  accounts: {
    oauth2: {
      initTokenClient: (cfg: {
        client_id: string;
        scope: string;
        callback: (r: TokenResponse) => void;
        error_callback?: (error: TokenClientError) => void;
      }) => TokenClient;
    };
  };
}

let gisLoading: Promise<void> | null = null;

function loadGis(): Promise<void> {
  if (gisLoading) return gisLoading;
  gisLoading = new Promise<void>((resolve, reject) => {
    if (gis()) return resolve();
    const script = document.createElement('script');
    script.src = GIS_SRC;
    script.async = true;
    script.defer = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Google Identity Services の読み込みに失敗しました'));
    document.head.appendChild(script);
  });
  return gisLoading;
}

function gis(): GisGlobal | undefined {
  return (globalThis as { google?: GisGlobal }).google;
}

/** GIS を初期化し、トークンを都度取得する `DriveTokenProvider` を返す。 */
export async function googleDriveTokens(clientId: string): Promise<DriveTokenProvider> {
  await loadGis();
  const google = gis();
  if (!google) throw new Error('Google Identity Services が利用できません');
  const client = google.accounts.oauth2.initTokenClient({ client_id: clientId, scope: SCOPE, callback: () => {} });

  return new CallbackTokenProvider(() => new Promise((resolve, reject) => {
    client.callback = (resp) => {
      if (resp.error) reject(new Error(resp.error));
      else resolve({ token: resp.access_token, expiresAt: Date.now() + (resp.expires_in ?? 3600) * 1000 });
    };
    // ポップアップを閉じる等で callback が一度も呼ばれないまま終わると、
    // ここを設定しないと accessToken() の Promise が永遠に待ち続ける。
    client.error_callback = (error) => {
      reject(new Error(error.message ?? error.type));
    };
    client.requestAccessToken();
  }));
}
