import type { RemoteStore, RemoteFileMeta, RemoteChanges } from './remoteStore';
import { RemoteConflictError, RemoteNotFoundError } from './remoteStore';

/**
 * テスト用のインメモリ `RemoteStore` 偽実装(iOS の InMemoryRemoteStore と同一挙動)。
 *
 * 競合シナリオ(§5.3)を Drive 無しでユニットテストするための継ぎ目。
 * 名前でファイルを管理し、書き込みごとに revision と changes 用の単調増加トークンを進める。
 */
interface Entry {
  meta: RemoteFileMeta;
  data: Uint8Array;
  /** changes 順序付け用の単調増加シーケンス。 */
  seq: number;
}

export class InMemoryRemoteStore implements RemoteStore {
  readonly displayName: string;

  private files = new Map<string, Entry>(); // name -> Entry
  private idToName = new Map<string, string>();
  private seqCounter = 0;
  private revCounter = 0;

  constructor(displayName = 'In-Memory') {
    this.displayName = displayName;
  }

  private nextSeq(): number { this.seqCounter += 1; return this.seqCounter; }
  private nextRev(): string { this.revCounter += 1; return `r${this.revCounter}`; }
  private nowIso(): string { return new Date().toISOString(); }

  async list(): Promise<RemoteFileMeta[]> {
    return [...this.files.values()]
      .filter((e) => !e.meta.deleted)
      .map((e) => e.meta)
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  }

  async read(id: string): Promise<Uint8Array> {
    const name = this.idToName.get(id);
    const entry = name ? this.files.get(name) : undefined;
    if (!entry || entry.meta.deleted) throw new RemoteNotFoundError(id);
    return entry.data;
  }

  async write(name: string, data: Uint8Array, ifMatch: string | null): Promise<RemoteFileMeta> {
    const existing = this.files.get(name);
    if (existing && !existing.meta.deleted) {
      // 楽観ロック: 期待 revision が現行と食い違えば衝突。
      if (ifMatch != null && ifMatch !== existing.meta.revision) {
        throw new RemoteConflictError(name, ifMatch, existing.meta.revision);
      }
      existing.data = data;
      existing.seq = this.nextSeq();
      existing.meta.revision = this.nextRev();
      existing.meta.updatedAt = this.nowIso();
      return existing.meta;
    }
    // ifMatch 指定があるのに対象が無い = 想定外(削除済みへの更新など)。
    if (ifMatch != null) {
      throw new RemoteConflictError(name, ifMatch, '<absent>');
    }
    const id = existing?.meta.id ?? crypto.randomUUID();
    const meta: RemoteFileMeta = { id, name, revision: this.nextRev(), updatedAt: this.nowIso(), deleted: false };
    this.files.set(name, { meta, data, seq: this.nextSeq() });
    this.idToName.set(id, name);
    return meta;
  }

  async delete(id: string): Promise<void> {
    const name = this.idToName.get(id);
    const entry = name ? this.files.get(name) : undefined;
    if (!entry) throw new RemoteNotFoundError(id);
    entry.meta.deleted = true;
    entry.meta.revision = this.nextRev();
    entry.seq = this.nextSeq();
    entry.data = new Uint8Array(0);
  }

  async changes(token: string | null): Promise<RemoteChanges> {
    const sinceSeq = token != null ? (Number.parseInt(token, 10) || 0) : 0;
    const changed = [...this.files.values()]
      .filter((e) => e.seq > sinceSeq)
      .sort((a, b) => a.seq - b.seq);
    const next = changed.length > 0 ? changed[changed.length - 1].seq : sinceSeq;
    // token=null(初回)はトークン確立のみで差分は返さない仕様に合わせる。
    const files = token == null ? [] : changed.map((e) => e.meta);
    return { files, nextToken: String(token == null ? this.seqCounter : next) };
  }

  // MARK: - テスト補助

  /** 別端末からの書き込みを模す(ifMatch 無しの直接投入)。 */
  async seed(name: string, data: Uint8Array): Promise<void> {
    await this.write(name, data, null);
  }

  currentRevision(name: string): string | null {
    return this.files.get(name)?.meta.revision ?? null;
  }
}
