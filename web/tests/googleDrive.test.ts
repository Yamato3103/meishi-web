import { describe, it, expect } from 'vitest';
import { GoogleDriveRemoteStore } from '../src/sync/googleDriveRemoteStore';
import { StaticTokenProvider, DriveError } from '../src/sync/driveHttp';
import type { DriveHttp, DriveHttpRequest, DriveHttpResponse } from '../src/sync/driveHttp';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/**
 * Google に接続せず、Drive REST の要求組み立て・応答解釈・競合判定を検証する。
 * パス + クエリ(復号後)の部分一致でスクリプト応答を返す偽サーバ(iOS の ScriptedDrive と同型)。
 */
class ScriptedDrive implements DriveHttp {
  private rules: { method: string; contains: string[]; response: DriveHttpResponse }[] = [];
  readonly requests: DriveHttpRequest[] = [];

  onJson(method: string, contains: string[], json: unknown): void {
    this.rules.push({ method, contains, response: { status: 200, data: encoder.encode(JSON.stringify(json)), headers: {} } });
  }
  onData(method: string, contains: string[], data: Uint8Array): void {
    this.rules.push({ method, contains, response: { status: 200, data, headers: {} } });
  }

  async send(request: DriveHttpRequest): Promise<DriveHttpResponse> {
    this.requests.push(request);
    const u = new URL(request.url);
    const decodedQuery = decodeURIComponent(u.searchParams.toString().replace(/\+/g, ' '));
    const hay = `${u.pathname}?${decodedQuery}`;
    for (const rule of this.rules) {
      if (rule.method === request.method && rule.contains.every((c) => hay.includes(c))) return rule.response;
    }
    return { status: 404, data: new Uint8Array(0), headers: {} };
  }
}

function makeStore(drive: ScriptedDrive): GoogleDriveRemoteStore {
  return new GoogleDriveRemoteStore({ tokens: new StaticTokenProvider('token-123'), http: drive });
}

const folderRule = ['/drive/v3/files', "mimeType='application/vnd.google-apps.folder'"];

describe('GoogleDriveRemoteStore(Drive REST v3 をモック HTTP で検証)', () => {
  it('list はファイルを解析し、全要求に Bearer トークンが付く', async () => {
    const drive = new ScriptedDrive();
    drive.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    drive.onJson('GET', ['/drive/v3/files', 'in parents and trashed=false'], { files: [
      { id: 'f1', name: 'a.json', version: '3', modifiedTime: '2026-08-08T06:16:21.000Z' },
      { id: 'f2', name: 'b.json', version: '7', modifiedTime: '2026-08-08T06:16:22.000Z' },
    ] });

    const metas = await makeStore(drive).list();
    expect(metas.map((m) => m.name)).toEqual(['a.json', 'b.json']);
    expect(metas[0].revision).toBe('3');
    expect(metas[0].updatedAt).toBe('2026-08-08T06:16:21.000Z');
    expect(drive.requests.every((r) => r.headers['Authorization'] === 'Bearer token-123')).toBe(true);
  });

  it('write は不在なら multipart で作成する', async () => {
    const drive = new ScriptedDrive();
    drive.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    drive.onJson('GET', ['/drive/v3/files', "name='c.json'"], { files: [] });
    drive.onJson('POST', ['/upload/drive/v3/files', 'uploadType=multipart'],
      { id: 'new1', name: 'c.json', version: '1', modifiedTime: '2026-08-08T06:16:21.000Z' });

    const meta = await makeStore(drive).write('c.json', encoder.encode('x'), null);
    expect(meta.id).toBe('new1');
    expect(meta.revision).toBe('1');
    expect(drive.requests.some((r) => r.method === 'POST' && r.url.includes('uploadType=multipart'))).toBe(true);
  });

  it('write は存在し version 一致なら media で更新する', async () => {
    const drive = new ScriptedDrive();
    drive.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    drive.onJson('GET', ['/drive/v3/files', "name='c.json'"],
      { files: [{ id: 'f9', name: 'c.json', version: '5', modifiedTime: '2026-08-08T06:16:21.000Z' }] });
    drive.onJson('PATCH', ['/upload/drive/v3/files/f9', 'uploadType=media'],
      { id: 'f9', name: 'c.json', version: '6', modifiedTime: '2026-08-08T06:16:30.000Z' });

    const meta = await makeStore(drive).write('c.json', encoder.encode('y'), '5');
    expect(meta.revision).toBe('6');
  });

  it('write は version 不一致なら衝突しアップロードしない', async () => {
    const drive = new ScriptedDrive();
    drive.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    drive.onJson('GET', ['/drive/v3/files', "name='c.json'"],
      { files: [{ id: 'f9', name: 'c.json', version: '5', modifiedTime: '2026-08-08T06:16:21.000Z' }] });

    await expect(makeStore(drive).write('c.json', encoder.encode('z'), '3')).rejects.toMatchObject({
      name: 'RemoteConflictError', expected: '3', actual: '5',
    });
    expect(drive.requests.some((r) => r.url.includes('/upload/'))).toBe(false);
  });

  it('changes は開始トークン → 差分の順に取得する', async () => {
    const boot = new ScriptedDrive();
    boot.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    boot.onJson('GET', ['/drive/v3/changes/startPageToken'], { startPageToken: '100' });

    const bootRes = await makeStore(boot).changes(null);
    expect(bootRes.files).toHaveLength(0);
    expect(bootRes.nextToken).toBe('100');

    const delta = new ScriptedDrive();
    delta.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    delta.onJson('GET', ['/drive/v3/changes', 'pageToken=100'], {
      changes: [{ file: { id: 'f1', name: 'a.json', version: '4', modifiedTime: '2026-08-08T06:16:21.000Z' } }],
      newStartPageToken: '105',
    });

    const deltaRes = await makeStore(delta).changes('100');
    expect(deltaRes.files.map((f) => f.name)).toEqual(['a.json']);
    expect(deltaRes.nextToken).toBe('105');
  });

  it('changes は removed=true を tombstone として返す', async () => {
    const drive = new ScriptedDrive();
    drive.onJson('GET', folderRule, { files: [{ id: 'folder1', name: 'MeishiVault' }] });
    drive.onJson('GET', ['/drive/v3/changes', 'pageToken=100'], {
      changes: [{ fileId: 'gone1', removed: true }],
      newStartPageToken: '106',
    });
    const res = await makeStore(drive).changes('100');
    expect(res.files).toHaveLength(1);
    expect(res.files[0].deleted).toBe(true);
    expect(res.files[0].id).toBe('gone1');
  });

  it('read は media を取得する', async () => {
    const drive = new ScriptedDrive();
    drive.onData('GET', ['/drive/v3/files/f1', 'alt=media'], encoder.encode('HELLO'));
    const data = await makeStore(drive).read('f1');
    expect(decoder.decode(data)).toBe('HELLO');
  });

  it('HTTP エラーは DriveError として表面化する', async () => {
    const drive = new ScriptedDrive(); // ルール無し → 404
    await expect(makeStore(drive).list()).rejects.toBeInstanceOf(DriveError);
  });
});
