import { describe, it, expect } from 'vitest';
import { NodeSqliteDriver } from '../src/db/nodeSqliteDriver';
import { runMigrations } from '../src/db/migrations';
import { CardRepository } from '../src/db/cardRepository';
import { makeCard } from '../src/core/card';
import { score } from '../src/core/duplicateDetector';

async function makeRepo(now: () => string = () => '2026-08-13T00:00:00.000Z') {
  const driver = NodeSqliteDriver.open();
  await runMigrations(driver);
  return new CardRepository(driver, 'test-device', now);
}

describe('重複検知(iOS DuplicateDetector / CardRepository と同一)', () => {
  // MARK: - スコアリング

  it('メール一致は +60(大文字小文字を無視)', () => {
    const a = makeCard({ id: 'a', email: 'Yamada@sample.co.jp' });
    const b = makeCard({ id: 'b', email: 'yamada@sample.co.jp' });
    expect(score(a, b)).toBe(60);
  });

  it('電話は書式を無視して数字一致で +40', () => {
    const a = makeCard({ id: 'a', phone: '03-1234-5678' });
    const b = makeCard({ id: 'b', mobile: '0312345678' });
    expect(score(a, b)).toBe(40);
  });

  it('氏名一致(+30)+ 会社正規化一致かつ姓一致(+20)= 50', () => {
    const a = makeCard({ id: 'a', familyName: '山田', givenName: '太郎', company: '株式会社サンプル商事' });
    const b = makeCard({ id: 'b', familyName: '山田', givenName: '太郎', company: 'サンプル商事' });
    expect(score(a, b)).toBe(50);
  });

  it('同じ会社でも姓が違えば加点なし', () => {
    const a = makeCard({ id: 'a', familyName: '山田', company: '株式会社サンプル商事' });
    const b = makeCard({ id: 'b', familyName: '鈴木', company: '株式会社サンプル商事' });
    expect(score(a, b)).toBe(0);
  });

  // MARK: - 検索(ブロッキング + 除外)

  it('findDuplicates はメールで候補を見つけ、強一致を立てる', async () => {
    const repo = await makeRepo();
    const existing = await repo.create(makeCard({ id: 'e', familyName: '山田', email: 'yamada@sample.co.jp' }));
    const draft = makeCard({ id: 'd', familyName: '山田', email: 'Yamada@Sample.co.jp' });

    const matches = await repo.findDuplicates(draft);
    expect(matches.map((m) => m.card.id)).toEqual([existing.id]);
    expect(matches[0].isStrong).toBe(true);
  });

  it('スコア降順で並ぶ', async () => {
    const repo = await makeRepo();
    // 候補2件: strong=メール一致(60)+氏名一致(30)=90、weak=電話一致(40)+氏名一致(30)=70。
    const strong = await repo.create(makeCard({ id: 's', familyName: '山田', email: 'y@x.jp' }));
    const weak = await repo.create(makeCard({ id: 'w', familyName: '山田', phone: '03-1234-5678' }));
    const draft = makeCard({ id: 'd', familyName: '山田', email: 'y@x.jp', phone: '03-1234-5678' });

    const matches = await repo.findDuplicates(draft);
    expect(matches.map((m) => m.card.id)).toEqual([strong.id, weak.id]);
    expect(matches[0].score).toBe(90);
    expect(matches[1].score).toBe(70);
  });

  it('別人確定済みのペアは候補に出ない', async () => {
    const repo = await makeRepo();
    const existing = await repo.create(makeCard({ id: 'e', familyName: '山田', email: 'yamada@sample.co.jp' }));
    const draft = await repo.create(makeCard({ id: 'd', familyName: '山田', email: 'yamada@sample.co.jp' }));
    await repo.markNotDuplicate(existing.id, draft.id);

    const matches = await repo.findDuplicates(draft);
    expect(matches).toHaveLength(0);
  });

  it('自分自身は候補にしない(id 除外)', async () => {
    const repo = await makeRepo();
    const card = await repo.create(makeCard({ id: 'c', email: 'y@x.jp' }));
    const matches = await repo.findDuplicates(card);
    expect(matches).toHaveLength(0);
  });

  // MARK: - マージ

  it('merge: 空欄補完・画像付替え・secondary を tombstone', async () => {
    const repo = await makeRepo();
    const primary = await repo.create(makeCard({ id: 'p', familyName: '山田', company: '株式会社サンプル商事', email: 'yamada@sample.co.jp' }));
    const secondary = await repo.create(makeCard({ id: 's', familyName: '山田', phone: '03-1234-5678', memo: '展示会で交換' }));
    await repo.addImage({ id: 'i1', cardId: secondary.id, side: 'front', relativePath: 's.jpg', sha256: 'x', width: null, height: null, createdAt: '2026-08-13T00:00:00.000Z' });

    const merged = await repo.merge(primary.id, secondary.id);

    expect(merged.email).toBe('yamada@sample.co.jp');
    expect(merged.phone).toBe('03-1234-5678'); // 空欄が secondary で補完
    expect(merged.memo).toBe('展示会で交換');
    expect(merged.revision).toBeGreaterThanOrEqual(2);

    // 画像が primary に移動。
    expect(await repo.fetchImages(primary.id)).toHaveLength(1);
    expect(await repo.fetchImages(secondary.id)).toHaveLength(0);

    // secondary は削除済み(一覧に出ない)。
    expect((await repo.fetchAll()).map((c) => c.id)).toEqual([primary.id]);
    expect((await repo.fetchOne(secondary.id))?.deletedAt).not.toBeNull();
  });

  it('merge: 両方メモありは改行連結・お気に入りは論理和', async () => {
    const repo = await makeRepo();
    const primary = await repo.create(makeCard({ id: 'p', familyName: '山田', memo: '一次', isFavorite: false }));
    const secondary = await repo.create(makeCard({ id: 's', familyName: '山田', memo: '二次', isFavorite: true }));

    const merged = await repo.merge(primary.id, secondary.id);
    expect(merged.memo).toBe('一次\n二次');
    expect(merged.isFavorite).toBe(true);
  });
});
