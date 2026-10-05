import type { CardRepository } from '../db/cardRepository';
import type { RemoteStore, RemoteFileMeta } from './remoteStore';
import { RemoteConflictError } from './remoteStore';
import type { ImageStore } from './imageStore';
import type { CardDocument, CardField } from '../core/cardDocument';
import { encodeDocument, decodeDocument, isDeleted } from '../core/cardDocument';
import type { FieldConflict } from '../core/lwwMerger';
import { mergeDocuments } from '../core/lwwMerger';
import { jsonEqual } from '../core/json';

/** 一度の同期の結果サマリ(UI 表示・診断用)。 */
export interface SyncSummary {
  pushed: number;
  pulled: number;
  deletionsPulled: number;
  /** フィールド単位 LWW で「負けた」値(名刺詳細の編集履歴に出せる)。 */
  conflicts: FieldConflict[];
}

function emptySummary(): SyncSummary {
  return { pushed: 0, pulled: 0, deletionsPulled: 0, conflicts: [] };
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();
function encode(doc: CardDocument): Uint8Array { return encoder.encode(encodeDocument(doc)); }
function decode(data: Uint8Array): CardDocument { return decodeDocument(decoder.decode(data)); }

/**
 * レコード単位のローカルファースト同期エンジン(§5)。iOS の MeishiKit.SyncEngine と同一設計。
 *
 * `RemoteStore` だけに依存し、Drive API を直接は呼ばない。
 * - push: dirty なカードを card.json 化してアップロード(楽観ロック If-Match)。
 *   衝突したらリモートを取得→フィールド単位 LWW でマージ→再アップロード。
 * - pull: 差分(初回は list=manifest 相当)を取得し、ローカルとマージして適用。
 *
 * 画像バイナリ本体は `imageStore` を渡したときだけ転送する(内容アドレス=相対パス、不変)。
 * 渡さなければ card.json(メタデータ)だけを収束させる。
 */
export class SyncEngine {
  static readonly manifestName = 'manifest.json';

  /** @param imageStore 画像バイナリの転送に使う。省略時はメタデータ(card.json)のみ同期する。 */
  constructor(
    private readonly repo: CardRepository,
    private readonly remote: RemoteStore,
    private readonly now: () => string = () => new Date().toISOString(),
    private readonly imageStore?: ImageStore,
  ) {}

  static fileName(cardId: string): string { return `${cardId}.json`; }

  /** push → pull を通しで実行する。 */
  async sync(): Promise<SyncSummary> {
    const summary = await this.push();
    const pulled = await this.pull();
    summary.pulled = pulled.pulled;
    summary.deletionsPulled = pulled.deletionsPulled;
    summary.conflicts = summary.conflicts.concat(pulled.conflicts);
    return summary;
  }

  // MARK: - push

  async push(): Promise<SyncSummary> {
    const summary = emptySummary();
    // 画像アップロードの重複回避用に、現在のリモートファイル名を一度だけ取得する。
    const existingNames = new Set<string>();
    if (this.imageStore) {
      for (const m of await this.remote.list()) existingNames.add(m.name);
    }
    for (const card of await this.repo.dirtyCards()) {
      const doc = await this.repo.buildDocument(card.id);
      if (!doc) continue;
      // card.json より先に画像本体を上げておく(受信側が参照を解決できるように)。
      await this.uploadImages(doc, existingNames);
      const name = SyncEngine.fileName(card.id);
      const ref = await this.repo.remoteRef(card.id);
      try {
        const meta = await this.remote.write(name, encode(doc), ref.remoteRevision);
        await this.repo.markSynced(card.id, meta.id, meta.revision, this.now());
        summary.pushed += 1;
      } catch (e) {
        if (!(e instanceof RemoteConflictError)) throw e;
        // リモートが先行 → 取得してマージし、マージ結果を現行版に対して再書き込み。
        const conflicts = await this.pushWithMerge(doc, card.id, name);
        summary.conflicts = summary.conflicts.concat(conflicts);
        summary.pushed += 1;
      }
    }
    return summary;
  }

  private async pushWithMerge(localDoc: CardDocument, cardId: string, name: string): Promise<FieldConflict[]> {
    const metas = await this.remote.list();
    const meta = metas.find((m) => m.name === name);
    if (!meta) {
      // 相手が消えた等 → 無条件で書き直す。
      const m = await this.remote.write(name, encode(localDoc), null);
      await this.repo.markSynced(cardId, m.id, m.revision, this.now());
      return [];
    }
    const remoteDoc = decode(await this.remote.read(meta.id));
    const result = mergeDocuments(localDoc, remoteDoc);
    // マージ結果をローカルへ反映(これから push するので未同期扱いにはしない)。
    await this.repo.applyRemoteDocument(result.document, meta.id, meta.revision, false);
    await this.repo.recordConflicts(cardId, result.conflicts);
    const written = await this.remote.write(name, encode(result.document), meta.revision);
    await this.repo.markSynced(cardId, written.id, written.revision, this.now());
    return result.conflicts;
  }

  // MARK: - pull

  async pull(): Promise<SyncSummary> {
    const summary = emptySummary();
    const token = await this.repo.syncToken();

    // 画像参照の解決(名前→メタ)用に、画像同期時は一覧を一度取得する。
    const catalog = new Map<string, RemoteFileMeta>();
    if (this.imageStore) {
      for (const m of await this.remote.list()) catalog.set(m.name, m);
    }

    if (token != null) {
      // 差分同期。
      const changes = await this.remote.changes(token);
      for (const meta of changes.files) await this.applyRemote(meta, catalog, summary);
      await this.repo.setSyncToken(changes.nextToken);
    } else {
      // 初回ブートストラップ: 先に開始トークンを確立し、その後 list(=manifest 相当)で全件取り込む。
      const start = await this.remote.changes(null);
      for (const meta of await this.remote.list()) await this.applyRemote(meta, catalog, summary);
      await this.repo.setSyncToken(start.nextToken);
    }
    return summary;
  }

  private async applyRemote(meta: RemoteFileMeta, catalog: Map<string, RemoteFileMeta>, summary: SyncSummary): Promise<void> {
    // card.json のみ対象。ファイル削除(meta.deleted)は扱わない:
    // 論理削除は deleted_at 付き card.json(tombstone)として流れてくる。
    if (!meta.name.endsWith('.json') || meta.name === SyncEngine.manifestName || meta.deleted) return;

    const remoteDoc = decode(await this.remote.read(meta.id));
    const cardId = remoteDoc.id;

    const localDoc = await this.repo.buildDocument(cardId);
    if (localDoc) {
      const result = mergeDocuments(localDoc, remoteDoc);
      // マージ結果がリモートと異なる=ローカル発の未 push 内容が残る → dirty のまま。
      const stillDirty = !contentEqual(result.document, remoteDoc);
      await this.repo.applyRemoteDocument(result.document, meta.id, meta.revision, stillDirty);
      await this.repo.recordConflicts(cardId, result.conflicts);
      summary.conflicts = summary.conflicts.concat(result.conflicts);
    } else {
      await this.repo.applyRemoteDocument(remoteDoc, meta.id, meta.revision, false);
    }

    // 参照されている画像で、ローカルに無いものを取得する。
    await this.downloadImages(remoteDoc, catalog);

    if (isDeleted(remoteDoc)) summary.deletionsPulled += 1;
    else summary.pulled += 1;
  }

  // MARK: - 画像バイナリ転送(内容アドレス=sha256、不変)

  private async uploadImages(doc: CardDocument, existing: Set<string>): Promise<void> {
    if (!this.imageStore) return;
    for (const ref of doc.images) {
      if (existing.has(ref.file)) continue;
      if (!(await this.imageStore.exists(ref.file))) continue;
      const data = await this.imageStore.read(ref.file);
      await this.remote.write(ref.file, data, null);
      existing.add(ref.file);
    }
  }

  private async downloadImages(doc: CardDocument, catalog: Map<string, RemoteFileMeta>): Promise<void> {
    if (!this.imageStore) return;
    for (const ref of doc.images) {
      if (await this.imageStore.exists(ref.file)) continue;
      const meta = catalog.get(ref.file);
      if (!meta || meta.deleted) continue;
      const data = await this.remote.read(meta.id);
      await this.imageStore.saveRaw(data, ref.file);
    }
  }
}

/** 同期対象の内容が等価か(device_id / revision / unknown は無視)。iOS contentEqual と同一。 */
function contentEqual(a: CardDocument, b: CardDocument): boolean {
  return fieldsEqual(a.fields, b.fields)
    && stringArraysEqual(a.tags, b.tags)
    && stringSetsEqual(a.images.map((i) => i.sha256), b.images.map((i) => i.sha256))
    && a.deletedAt === b.deletedAt
    && a.ocrFulltext === b.ocrFulltext;
}

function fieldsEqual(a: Record<string, CardField>, b: Record<string, CardField>): boolean {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    const fa = a[k];
    const fb = b[k];
    if (!fa || !fb) return false;
    if (fa.t !== fb.t || !jsonEqual(fa.v, fb.v)) return false;
  }
  return true;
}

function stringArraysEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((v, i) => v === b[i]);
}

function stringSetsEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const sb = new Set(b);
  return a.every((v) => sb.has(v));
}
