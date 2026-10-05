import { describe, it, expect } from 'vitest';
import { NodeSqliteDriver } from '../src/db/nodeSqliteDriver';
import { runMigrations } from '../src/db/migrations';
import { CardRepository } from '../src/db/cardRepository';
import { makeCard } from '../src/core/card';
import { InMemoryRemoteStore } from '../src/sync/inMemoryRemoteStore';
import { MemoryImageStore } from '../src/sync/imageStore';
import { SyncEngine } from '../src/sync/syncEngine';

const enc = new TextEncoder();
const dec = new TextDecoder();

/** 可変クロック(repo と engine で同じ参照を共有)。 */
interface Clock { t: string }

async function makeDevice(deviceId: string, clock: Clock) {
  const driver = NodeSqliteDriver.open();
  await runMigrations(driver);
  const repo = new CardRepository(driver, deviceId, () => clock.t);
  return { repo };
}

const T0 = '2026-08-14T00:00:00.000Z';
const TA = '2026-08-14T01:00:00.000Z';
const TB = '2026-08-14T02:00:00.000Z';

describe('SyncEngine(iOS と同一の card.json 収束・2端末 + 共有偽ストア)', () => {
  it('新規は片方 push → もう片方 pull で伝播する', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const cb: Clock = { t: T0 };
    const { repo: repoA } = await makeDevice('A', ca);
    const { repo: repoB } = await makeDevice('B', cb);
    const engA = new SyncEngine(repoA, remote, () => ca.t);
    const engB = new SyncEngine(repoB, remote, () => cb.t);

    await repoA.create(makeCard({ id: 'c1', familyName: '山田', email: 'y@x.jp' }));
    const sa = await engA.sync();
    expect(sa.pushed).toBe(1);

    const sb = await engB.sync();
    expect(sb.pulled).toBe(1);
    const b = await repoB.fetchOne('c1');
    expect(b?.familyName).toBe('山田');
    expect(b?.email).toBe('y@x.jp');
    expect(b?.dirty).toBe(false);
    // 正規化キーは各端末で再計算される。
    expect(b?.emailNormalized).toBe('y@x.jp');
  });

  it('同一フィールド競合はLWWで収束し、負けた値を両端末の履歴に残す', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const cb: Clock = { t: T0 };
    const { repo: repoA } = await makeDevice('A', ca);
    const { repo: repoB } = await makeDevice('B', cb);
    const engA = new SyncEngine(repoA, remote, () => ca.t);
    const engB = new SyncEngine(repoB, remote, () => cb.t);

    // 収束: 両端末が c1(山田)を持つ。
    await repoA.create(makeCard({ id: 'c1', familyName: '山田' }));
    await engA.sync();
    await engB.sync();

    // A は山田A(TA)、B は山田B(TB>TA=Bが勝つ)に同一フィールドを編集。
    ca.t = TA;
    const a0 = await repoA.fetchOne('c1');
    await repoA.update({ ...a0!, familyName: '山田A' });
    cb.t = TB;
    const b0 = await repoB.fetchOne('c1');
    await repoB.update({ ...b0!, familyName: '山田B' });

    // A が先に push。次に B が push(衝突→マージ)。その後 A が pull で追従。
    await engA.sync();
    await engB.sync();
    await engA.sync();
    await engB.sync();

    const a = await repoA.fetchOne('c1');
    const b = await repoB.fetchOne('c1');
    expect(a?.familyName).toBe('山田B');
    expect(b?.familyName).toBe('山田B');
    expect(a?.dirty).toBe(false);
    expect(b?.dirty).toBe(false);

    const ca2 = await repoA.conflicts('c1');
    const cb2 = await repoB.conflicts('c1');
    expect(ca2.some((c) => c.field === 'family_name' && c.losingValue === '山田A')).toBe(true);
    expect(cb2.some((c) => c.field === 'family_name' && c.losingValue === '山田A')).toBe(true);
  });

  it('論理削除(tombstone)は card.json として伝播する', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const cb: Clock = { t: T0 };
    const { repo: repoA } = await makeDevice('A', ca);
    const { repo: repoB } = await makeDevice('B', cb);
    const engA = new SyncEngine(repoA, remote, () => ca.t);
    const engB = new SyncEngine(repoB, remote, () => cb.t);

    await repoA.create(makeCard({ id: 'c1', familyName: '山田' }));
    await engA.sync();
    await engB.sync();
    expect((await repoB.fetchAll()).length).toBe(1);

    ca.t = TA;
    await repoA.softDelete('c1');
    await engA.sync();

    const sb = await engB.sync();
    expect(sb.deletionsPulled).toBe(1);
    expect((await repoB.fetchOne('c1'))?.deletedAt).not.toBeNull();
    expect((await repoB.fetchAll()).length).toBe(0); // 一覧から消える
  });

  it('タグの付与が伝播する', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const cb: Clock = { t: T0 };
    const { repo: repoA } = await makeDevice('A', ca);
    const { repo: repoB } = await makeDevice('B', cb);
    const engA = new SyncEngine(repoA, remote, () => ca.t);
    const engB = new SyncEngine(repoB, remote, () => cb.t);

    await repoA.create(makeCard({ id: 'c1', familyName: '山田' }));
    await engA.sync();
    await engB.sync();

    ca.t = TA;
    const tag = await repoA.createOrGetTag('取引先');
    await repoA.addTag(tag.id, 'c1');
    await engA.sync();

    await engB.sync();
    const tags = await repoB.tags('c1');
    expect(tags.map((t) => t.name)).toContain('取引先');
  });

  it('画像バイナリが2端末間で伝播する', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const cb: Clock = { t: T0 };
    const isA = new MemoryImageStore();
    const isB = new MemoryImageStore();
    const { repo: repoA } = await makeDevice('A', ca);
    const { repo: repoB } = await makeDevice('B', cb);
    const engA = new SyncEngine(repoA, remote, () => ca.t, isA);
    const engB = new SyncEngine(repoB, remote, () => cb.t, isB);

    await repoA.create(makeCard({ id: 'c1', familyName: '山田' }));
    await repoA.addImage({ id: 'i1', cardId: 'c1', side: 'front', relativePath: 'c1_front.jpg', sha256: 'sha1', width: null, height: null, createdAt: T0 });
    await isA.saveRaw(enc.encode('JPEGDATA'), 'c1_front.jpg');
    await engA.sync();

    const sb = await engB.sync();
    expect(sb.pulled).toBe(1);
    // 画像本体が B のストアに届く。
    expect(await isB.exists('c1_front.jpg')).toBe(true);
    expect(dec.decode(await isB.read('c1_front.jpg'))).toBe('JPEGDATA');
    // 画像の DB 行も B 側に再現される。
    const imgs = await repoB.fetchImages('c1');
    expect(imgs.map((i) => i.relativePath)).toContain('c1_front.jpg');
  });

  it('imageStore を渡さなければ card.json だけ同期する(画像は無視)', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const cb: Clock = { t: T0 };
    const { repo: repoA } = await makeDevice('A', ca);
    const { repo: repoB } = await makeDevice('B', cb);
    const engA = new SyncEngine(repoA, remote, () => ca.t); // imageStore 無し
    const engB = new SyncEngine(repoB, remote, () => cb.t);

    await repoA.create(makeCard({ id: 'c1', familyName: '山田' }));
    await repoA.addImage({ id: 'i1', cardId: 'c1', side: 'front', relativePath: 'c1_front.jpg', sha256: 'sha1', width: null, height: null, createdAt: T0 });
    await engA.sync();
    const sb = await engB.sync();

    expect(sb.pulled).toBe(1);
    // メタ(card_images 行)は伝播するが、バイナリ転送は行われない。
    expect((await repoB.fetchImages('c1')).map((i) => i.relativePath)).toContain('c1_front.jpg');
  });

  it('同期は冪等: 変更が無ければ再 sync で何も起きない', async () => {
    const remote = new InMemoryRemoteStore();
    const ca: Clock = { t: T0 };
    const { repo: repoA } = await makeDevice('A', ca);
    const engA = new SyncEngine(repoA, remote, () => ca.t);
    await repoA.create(makeCard({ id: 'c1', familyName: '山田' }));
    await engA.sync();
    const again = await engA.sync();
    expect(again.pushed).toBe(0);
    expect(again.pulled).toBe(0);
    expect((await repoA.fetchOne('c1'))?.dirty).toBe(false);
  });
});
