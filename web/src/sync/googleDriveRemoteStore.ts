import type { RemoteStore, RemoteFileMeta, RemoteChanges } from './remoteStore';
import { RemoteConflictError } from './remoteStore';
import type { DriveHttp, DriveHttpRequest, DriveTokenProvider } from './driveHttp';
import { FetchDriveHttp, DriveError } from './driveHttp';

const API_BASE = 'https://www.googleapis.com/drive/v3';
const UPLOAD_BASE = 'https://www.googleapis.com/upload/drive/v3';
const FOLDER_MIME = 'application/vnd.google-apps.folder';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/**
 * Google Drive を裏側にする `RemoteStore` 実装(Drive REST API v3、`drive.file` スコープ)。
 * iOS の MeishiKit.GoogleDriveRemoteStore と同一挙動。
 *
 * - マイドライブ直下に作業フォルダ(既定 "MeishiVault")を作り、その中に card.json と画像を置く。
 *   `drive.file` は「自アプリ作成ファイルのみ」可視のため、フォルダ選択 UI は提供せず自動作成する。
 * - 楽観ロックはファイルの `version`(単調増加)を使った check-then-act で表現する。
 *
 * ネットワーク送信は `DriveHttp`、認可は `DriveTokenProvider` に委譲するため、Google に接続せずとも
 * REST ロジックをモックで検証できる。実サインインは各自の Google Cloud OAuth 設定が必要
 * (docs/web-google-drive-setup.md)。
 */
export class GoogleDriveRemoteStore implements RemoteStore {
  readonly displayName: string;

  private readonly http: DriveHttp;
  private readonly tokens: DriveTokenProvider;
  private readonly folderName: string;
  private cachedFolderId: string | null = null;

  constructor(options: {
    tokens: DriveTokenProvider;
    http?: DriveHttp;
    folderName?: string;
    displayName?: string;
  }) {
    this.tokens = options.tokens;
    this.http = options.http ?? new FetchDriveHttp();
    this.folderName = options.folderName ?? 'MeishiVault';
    this.displayName = options.displayName ?? 'Google Drive';
  }

  // MARK: - RemoteStore

  async list(): Promise<RemoteFileMeta[]> {
    const folderId = await this.ensureFolder();
    const metas: RemoteFileMeta[] = [];
    let pageToken: string | undefined;
    do {
      const query: Record<string, string> = {
        q: `'${folderId}' in parents and trashed=false`,
        spaces: 'drive',
        fields: 'nextPageToken,files(id,name,version,modifiedTime)',
        pageSize: '1000',
      };
      if (pageToken) query['pageToken'] = pageToken;
      const json = await this.getJSON(`${API_BASE}/files`, query);
      for (const file of asArray(json['files'])) {
        const meta = metaFrom(file, false);
        if (meta) metas.push(meta);
      }
      pageToken = typeof json['nextPageToken'] === 'string' ? json['nextPageToken'] : undefined;
    } while (pageToken);
    return metas.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  }

  async read(id: string): Promise<Uint8Array> {
    const token = await this.tokens.accessToken();
    return this.requestData(this.makeRequest(`${API_BASE}/files/${id}`, { alt: 'media' }, 'GET', token));
  }

  async write(name: string, data: Uint8Array, ifMatch: string | null): Promise<RemoteFileMeta> {
    const folderId = await this.ensureFolder();
    const existing = await this.findFile(name, folderId);
    if (existing) {
      if (ifMatch != null && ifMatch !== existing.revision) {
        throw new RemoteConflictError(name, ifMatch, existing.revision);
      }
      return this.updateMedia(existing.id, name, data);
    }
    if (ifMatch != null) {
      throw new RemoteConflictError(name, ifMatch, '<absent>');
    }
    return this.createMultipart(name, data, folderId);
  }

  async delete(id: string): Promise<void> {
    const token = await this.tokens.accessToken();
    const response = await this.http.send(this.makeRequest(`${API_BASE}/files/${id}`, {}, 'DELETE', token));
    ensureOK(response);
  }

  async changes(token: string | null): Promise<RemoteChanges> {
    await this.ensureFolder();
    if (token == null) {
      const json = await this.getJSON(`${API_BASE}/changes/startPageToken`, { fields: 'startPageToken' });
      const start = typeof json['startPageToken'] === 'string' ? json['startPageToken'] : '1';
      return { files: [], nextToken: start };
    }

    const files: RemoteFileMeta[] = [];
    let pageToken: string | undefined = token;
    let newStartToken = token;
    do {
      const query: Record<string, string> = {
        pageToken: pageToken ?? token,
        spaces: 'drive',
        fields: 'newStartPageToken,nextPageToken,changes(fileId,removed,file(id,name,version,modifiedTime,trashed))',
      };
      const json = await this.getJSON(`${API_BASE}/changes`, query);
      for (const change of asArray(json['changes'])) {
        const removed = change['removed'] === true;
        if (removed) {
          const id = change['fileId'];
          if (typeof id === 'string') files.push({ id, name: '', revision: '', updatedAt: null, deleted: true });
        } else if (change['file'] && typeof change['file'] === 'object') {
          const file = change['file'] as Record<string, unknown>;
          const trashed = file['trashed'] === true;
          const meta = metaFrom(file, trashed);
          if (meta) files.push(meta);
        }
      }
      const next = json['nextPageToken'];
      if (typeof next === 'string') {
        pageToken = next;
      } else {
        newStartToken = typeof json['newStartPageToken'] === 'string' ? json['newStartPageToken'] : token;
        pageToken = undefined;
      }
    } while (pageToken);

    return { files, nextToken: newStartToken };
  }

  // MARK: - フォルダ

  private async ensureFolder(): Promise<string> {
    if (this.cachedFolderId) return this.cachedFolderId;
    const escapedFolderName = this.folderName.replace(/'/g, "\\'");
    const query = {
      q: `name='${escapedFolderName}' and mimeType='${FOLDER_MIME}' and trashed=false`,
      spaces: 'drive',
      fields: 'files(id,name)',
    };
    const json = await this.getJSON(`${API_BASE}/files`, query);
    const first = asArray(json['files'])[0];
    if (first && typeof first['id'] === 'string') {
      this.cachedFolderId = first['id'];
      return first['id'];
    }
    // 無ければ作成する。
    const token = await this.tokens.accessToken();
    const request = this.makeRequest(`${API_BASE}/files`, { fields: 'id' }, 'POST', token);
    request.headers['Content-Type'] = 'application/json; charset=UTF-8';
    request.body = encoder.encode(JSON.stringify({ name: this.folderName, mimeType: FOLDER_MIME }));
    const created = await this.sendJSON(request);
    if (typeof created['id'] !== 'string') throw DriveError.decoding('folder id');
    this.cachedFolderId = created['id'];
    return created['id'];
  }

  private async findFile(name: string, folderId: string): Promise<RemoteFileMeta | null> {
    const escaped = name.replace(/'/g, "\\'");
    const query = {
      q: `name='${escaped}' and '${folderId}' in parents and trashed=false`,
      spaces: 'drive',
      fields: 'files(id,name,version,modifiedTime)',
    };
    const json = await this.getJSON(`${API_BASE}/files`, query);
    const first = asArray(json['files'])[0];
    return first ? metaFrom(first, false) : null;
  }

  // MARK: - アップロード

  private async updateMedia(fileId: string, name: string, data: Uint8Array): Promise<RemoteFileMeta> {
    const token = await this.tokens.accessToken();
    const request = this.makeRequest(`${UPLOAD_BASE}/files/${fileId}`,
      { uploadType: 'media', fields: 'id,name,version,modifiedTime' }, 'PATCH', token);
    request.headers['Content-Type'] = 'application/octet-stream';
    request.body = data;
    const json = await this.sendJSON(request);
    const meta = metaFrom(json, false, name);
    if (!meta) throw DriveError.decoding('update media response');
    return meta;
  }

  private async createMultipart(name: string, data: Uint8Array, parent: string): Promise<RemoteFileMeta> {
    const boundary = `meishi-${crypto.randomUUID()}`;
    const metadata = JSON.stringify({ name, parents: [parent] });
    const body = concatBytes([
      encoder.encode(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n`),
      encoder.encode(metadata),
      encoder.encode(`\r\n--${boundary}\r\nContent-Type: application/octet-stream\r\n\r\n`),
      data,
      encoder.encode(`\r\n--${boundary}--\r\n`),
    ]);

    const token = await this.tokens.accessToken();
    const request = this.makeRequest(`${UPLOAD_BASE}/files`,
      { uploadType: 'multipart', fields: 'id,name,version,modifiedTime' }, 'POST', token);
    request.headers['Content-Type'] = `multipart/related; boundary=${boundary}`;
    request.body = body;
    const json = await this.sendJSON(request);
    const meta = metaFrom(json, false, name);
    if (!meta) throw DriveError.decoding('create response');
    return meta;
  }

  // MARK: - 低レベル HTTP

  private makeRequest(base: string, query: Record<string, string>, method: string, token: string): DriveHttpRequest {
    const url = Object.keys(query).length > 0 ? `${base}?${new URLSearchParams(query).toString()}` : base;
    return { url, method, headers: { Authorization: `Bearer ${token}` } };
  }

  private async getJSON(base: string, query: Record<string, string>): Promise<Record<string, unknown>> {
    const token = await this.tokens.accessToken();
    return this.sendJSON(this.makeRequest(base, query, 'GET', token));
  }

  private async sendJSON(request: DriveHttpRequest): Promise<Record<string, unknown>> {
    const response = await this.http.send(request);
    ensureOK(response);
    try {
      const obj = JSON.parse(decoder.decode(response.data)) as unknown;
      if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) throw new Error('not object');
      return obj as Record<string, unknown>;
    } catch {
      throw DriveError.decoding('expected JSON object');
    }
  }

  private async requestData(request: DriveHttpRequest): Promise<Uint8Array> {
    const response = await this.http.send(request);
    ensureOK(response);
    return response.data;
  }
}

// MARK: - ヘルパー

function ensureOK(response: { status: number; data: Uint8Array }): void {
  if (response.status < 200 || response.status >= 300) {
    throw DriveError.http(response.status, decoder.decode(response.data));
  }
}

function asArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? (value as Record<string, unknown>[]) : [];
}

function metaFrom(file: Record<string, unknown>, deleted: boolean, fallbackName = ''): RemoteFileMeta | null {
  if (typeof file['id'] !== 'string') return null;
  const name = typeof file['name'] === 'string' ? file['name'] : fallbackName;
  // version は int64 が数値または文字列で来る。どちらも文字列化する。
  const rawVersion = file['version'];
  const revision = typeof rawVersion === 'string' ? rawVersion
    : typeof rawVersion === 'number' ? String(rawVersion) : '';
  const updatedAt = typeof file['modifiedTime'] === 'string' ? file['modifiedTime'] : null;
  return { id: file['id'], name, revision, updatedAt, deleted };
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) { out.set(p, offset); offset += p.length; }
  return out;
}
