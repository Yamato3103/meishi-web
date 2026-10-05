/**
 * Drive 連携の HTTP 抽象と認可の継ぎ目(iOS の DriveHTTP.swift と同一設計)。
 *
 * `GoogleDriveRemoteStore` は `fetch` を直接使わず `DriveHttp` に委譲するため、
 * Google に接続せずとも REST ロジック(要求組み立て・応答解釈・競合判定)をモックで検証できる。
 * 認可は `DriveTokenProvider` に分離し、OAuth 実装(トークン取得/更新)を同期ロジックから切り離す。
 */

/** HTTP リクエスト(継ぎ目用の最小表現)。 */
export interface DriveHttpRequest {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: Uint8Array;
}

/** HTTP レスポンス(継ぎ目用の最小表現)。 */
export interface DriveHttpResponse {
  status: number;
  data: Uint8Array;
  headers: Record<string, string>;
}

/** HTTP 送信の抽象。 */
export interface DriveHttp {
  send(request: DriveHttpRequest): Promise<DriveHttpResponse>;
}

/** `fetch` 実装(本番・ブラウザ)。 */
export class FetchDriveHttp implements DriveHttp {
  async send(request: DriveHttpRequest): Promise<DriveHttpResponse> {
    const res = await fetch(request.url, {
      method: request.method,
      headers: request.headers,
      body: request.body as BodyInit | undefined,
    });
    const buf = new Uint8Array(await res.arrayBuffer());
    const headers: Record<string, string> = {};
    res.headers.forEach((value, key) => { headers[key] = value; });
    return { status: res.status, data: buf, headers };
  }
}

/** アクセストークンの供給元。OAuth の実装をストアから分離する。 */
export interface DriveTokenProvider {
  /** 有効なアクセストークンを返す(必要なら内部で更新する)。 */
  accessToken(): Promise<string>;
}

/** 固定トークンを返す(テスト・簡易利用向け)。 */
export class StaticTokenProvider implements DriveTokenProvider {
  constructor(private readonly token: string) {}
  async accessToken(): Promise<string> { return this.token; }
}

/**
 * 呼び出し側の関数にトークン取得を委譲するプロバイダ。
 * アプリは Google Identity Services(GIS)のトークンクライアントなどでこの関数を実装する。
 * 期限(expiresAt, epoch ms)を返した場合は、期限の 60 秒前まではキャッシュを再利用する。
 */
export class CallbackTokenProvider implements DriveTokenProvider {
  private cached: { token: string; expiresAt: number } | null = null;

  constructor(private readonly fetcher: () => Promise<{ token: string; expiresAt?: number }>) {}

  async accessToken(): Promise<string> {
    const now = Date.now();
    if (this.cached && this.cached.expiresAt - 60_000 > now) return this.cached.token;
    const { token, expiresAt } = await this.fetcher();
    this.cached = { token, expiresAt: expiresAt ?? now + 3_500_000 };
    return token;
  }

  /** キャッシュを破棄する(サインアウトや失効時)。 */
  reset(): void { this.cached = null; }
}

/** Drive 連携のエラー。 */
export class DriveError extends Error {
  constructor(
    public readonly kind: 'invalid-response' | 'http' | 'decoding' | 'not-found',
    message: string,
    public readonly status?: number,
    public readonly body?: string,
  ) {
    super(message);
    this.name = 'DriveError';
  }

  static http(status: number, body: string): DriveError {
    return new DriveError('http', `Drive HTTP ${status}: ${body}`, status, body);
  }
  static decoding(what: string): DriveError {
    return new DriveError('decoding', `Drive decoding failed: ${what}`);
  }
}
