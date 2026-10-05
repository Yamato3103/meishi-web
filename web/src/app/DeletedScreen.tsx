import { useCallback, useEffect, useState } from 'react';
import type { Card } from '../core';
import type { OpenedDatabase } from './database';
import { s, fullName } from './ui';

/** 最近削除: 復元 / 完全削除。 */
export function DeletedScreen({ db, onBack }: { db: OpenedDatabase; onBack: () => void }) {
  const [cards, setCards] = useState<Card[]>([]);

  const load = useCallback(async () => {
    setCards(await db.repo.fetchDeleted());
  }, [db]);

  useEffect(() => { void load(); }, [load]);

  const restore = async (id: string) => { await db.repo.restore(id); await load(); };
  const purge = async (id: string) => { await db.repo.permanentlyDelete(id); await load(); };

  return (
    <div>
      <div style={s.topbar}>
        <button style={s.iconButton} onClick={onBack}>← 戻る</button>
        <h1 style={s.title}>最近削除</h1>
      </div>

      {cards.length === 0 ? (
        <p style={s.empty}>削除した名刺はありません。</p>
      ) : (
        <ul style={s.list}>
          {cards.map((card) => (
            <li key={card.id} style={{ ...s.row, cursor: 'default' }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={s.name}>{fullName(card) || '(名前なし)'}</div>
                {card.company && <div style={s.sub}>{card.company}</div>}
              </div>
              <button style={s.ghost} onClick={() => restore(card.id)}>復元</button>
              <button style={s.danger} onClick={() => purge(card.id)}>完全削除</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
