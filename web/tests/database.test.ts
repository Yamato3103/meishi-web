import { describe, it, expect } from 'vitest';
import { NodeSqliteDriver } from '../src/db/nodeSqliteDriver';
import { runMigrations, MIGRATIONS } from '../src/db/migrations';
import { CardRepository } from '../src/db/cardRepository';
import { makeCard } from '../src/core/card';

async function makeRepo(now: () => string = () => '2026-08-08T00:00:00.000Z') {
  const driver = NodeSqliteDriver.open();
  await runMigrations(driver);
  return { repo: new CardRepository(driver, 'test-device', now), driver };
}

describe('database (node:sqlite / wa-sqlite と同じ SQLite 方言)', () => {
  it('マイグレーションは冪等で、全テーブルを作る', async () => {
    const driver = NodeSqliteDriver.open();
    await runMigrations(driver);
    await runMigrations(driver); // 2回目も安全

    const applied = await driver.all<{ name: string }>('SELECT name FROM _migrations');
    expect(applied).toHaveLength(MIGRATIONS.length);

    const tables = await driver.all<{ name: string }>("SELECT name FROM sqlite_master WHERE type='table'");
    const names = tables.map((t) => t.name);
    for (const expected of ['cards', 'card_images', 'not_duplicate_pairs', 'tags', 'card_tags', 'sync_kv', 'card_remote', 'field_conflicts']) {
      expect(names).toContain(expected);
    }
  });

  it('create は revision=1・dirty・正規化キーを立てる', async () => {
    const { repo } = await makeRepo();
    const c = await repo.create(makeCard({ id: 'c1', familyName: '山田', company: '株式会社サンプル商事', email: 'A@B.com' }));
    expect(c.revision).toBe(1);
    expect(c.dirty).toBe(true);
    expect(c.emailNormalized).toBe('a@b.com');
    expect(c.companyNormalized).toBe('サンプル商事');

    const fetched = await repo.fetchOne('c1');
    expect(fetched?.familyName).toBe('山田');
    expect(fetched?.isFavorite).toBe(false);
  });

  it('update は revision++ し、変更フィールドの時刻だけ更新', async () => {
    const clock = { t: '2026-08-08T00:00:00.000Z' };
    const { repo } = await makeRepo(() => clock.t);
    const c = await repo.create(makeCard({ id: 'c1', familyName: '山田', company: 'A社' }));

    const ts0 = await repo.fieldTimestamps('c1');
    expect(ts0['company']).toBe('2026-08-08T00:00:00.000Z');
    expect(ts0['family_name']).toBe('2026-08-08T00:00:00.000Z');

    clock.t = '2026-08-09T00:00:00.000Z';
    const updated = await repo.update({ ...c, company: 'B社' });
    expect(updated.revision).toBe(2);

    const ts1 = await repo.fieldTimestamps('c1');
    expect(ts1['company']).toBe('2026-08-09T00:00:00.000Z'); // 変更 → 新時刻
    expect(ts1['family_name']).toBe('2026-08-08T00:00:00.000Z'); // 未変更 → 据え置き
  });

  it('検索: 3文字以上=FTS5 trigram / 2文字以下=LIKE / 削除除外', async () => {
    const { repo } = await makeRepo();
    await repo.create(makeCard({ id: 'a', familyName: '山田', familyNameKana: 'やまだ', company: '株式会社サンプル商事' }));
    await repo.create(makeCard({ id: 'b', familyName: '鈴木', company: 'テスト工業' }));

    expect((await repo.search('サンプル')).map((c) => c.id)).toEqual(['a']); // FTS(4文字)
    expect((await repo.search('やま')).map((c) => c.id)).toEqual(['a']);     // LIKE(2文字・かな)
    expect((await repo.search('工業')).map((c) => c.id)).toEqual(['b']);     // LIKE(2文字・会社)

    await repo.softDelete('a');
    expect(await repo.search('サンプル')).toHaveLength(0); // 削除は除外
  });

  it('fetchAll は更新日時の降順', async () => {
    const clock = { t: '2026-08-08T00:00:00.000Z' };
    const { repo } = await makeRepo(() => clock.t);
    await repo.create(makeCard({ id: 'old', familyName: '旧' }));
    clock.t = '2026-08-09T00:00:00.000Z';
    await repo.create(makeCard({ id: 'new', familyName: '新' }));
    expect((await repo.fetchAll()).map((c) => c.id)).toEqual(['new', 'old']);
  });

  it('タグ: 正規化 dedupe・付与・絞り込み・削除', async () => {
    const { repo } = await makeRepo();
    const card = await repo.create(makeCard({ id: 'c1', familyName: '山田' }));

    const t1 = await repo.createOrGetTag('  取引先 ');
    const t1b = await repo.createOrGetTag('取引先');
    expect(t1.id).toBe(t1b.id); // 正規化一致は同じタグ

    await repo.addTag(t1.id, card.id);
    expect(await repo.tags('c1')).toHaveLength(1);
    expect([...(await repo.cardIds(t1.id))]).toEqual(['c1']);

    // addTag はカードを touch(revision++/dirty)
    expect((await repo.fetchOne('c1'))?.revision).toBe(2);

    await repo.removeTag(t1.id, card.id);
    expect(await repo.tags('c1')).toHaveLength(0);

    const t2 = await repo.createOrGetTag('重要');
    await repo.addTag(t2.id, card.id);
    await repo.deleteTag(t2.id);
    expect((await repo.allTags()).map((t) => t.name)).toEqual(['取引先']); // 重要は消え、付与も外れる
    expect(await repo.tags('c1')).toHaveLength(0);
  });

  it('画像の保存と取得', async () => {
    const { repo } = await makeRepo();
    await repo.create(makeCard({ id: 'c1', familyName: '山田' }));
    await repo.addImage({ id: 'i1', cardId: 'c1', side: 'front', relativePath: 'c1-front.jpg', sha256: 'sha', width: 1000, height: 600, createdAt: '2026-08-08T00:00:00.000Z' });
    const images = await repo.fetchImages('c1');
    expect(images.map((i) => i.sha256)).toEqual(['sha']);
    expect(images[0].relativePath).toBe('c1-front.jpg');
  });
});
