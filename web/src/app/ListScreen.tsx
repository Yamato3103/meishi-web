import { useCallback, useEffect, useState } from 'react';
import type { Card } from '../core';
import type { OpenedDatabase } from './database';
import type { Tag } from '../db';
import { s, fullName } from './ui';

/** 一覧: 検索 + タグ絞り込み + 行タップで詳細。追加/設定への導線。 */
export function ListScreen({
  db, onOpen, onNew, onCapture, onSettings,
}: {
  db: OpenedDatabase;
  onOpen: (id: string) => void;
  onNew: () => void;
  onCapture: () => void;
  onSettings: () => void;
}) {
  const [query, setQuery] = useState('');
  const [cards, setCards] = useState<Card[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [activeTag, setActiveTag] = useState<string | null>(null);

  const reload = useCallback(async (q: string, tagId: string | null) => {
    const base = q.trim() ? await db.repo.search(q) : await db.repo.fetchAll();
    if (tagId) {
      const ids = await db.repo.cardIds(tagId);
      setCards(base.filter((c) => ids.has(c.id)));
    } else {
      setCards(base);
    }
    setTags(await db.repo.allTags());
  }, [db]);

  useEffect(() => {
    const handle = setTimeout(() => { void reload(query, activeTag); }, 150);
    return () => clearTimeout(handle);
  }, [query, activeTag, reload]);

  return (
    <div>
      <div style={s.topbar}>
        <h1 style={s.title}>MeishiVault</h1>
        <button style={s.iconButton} onClick={onSettings} aria-label="設定">⚙︎</button>
        <button style={s.iconButton} onClick={onNew}>＋ 手入力</button>
        <button style={s.primary} onClick={onCapture}>📷 取り込み</button>
      </div>

      <input
        style={s.search}
        type="search"
        placeholder="検索(氏名・会社・メール・住所…)"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        aria-label="名刺を検索"
      />

      {tags.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.4rem', marginTop: '0.6rem' }}>
          <button style={{ ...s.chipButton, ...(activeTag === null ? s.chipButtonOn : {}) }} onClick={() => setActiveTag(null)}>すべて</button>
          {tags.map((t) => (
            <button
              key={t.id}
              style={{ ...s.chipButton, ...(activeTag === t.id ? s.chipButtonOn : {}) }}
              onClick={() => setActiveTag((cur) => (cur === t.id ? null : t.id))}
            >
              #{t.name}
            </button>
          ))}
        </div>
      )}

      <p style={s.count}>
        {query.trim() ? `「${query.trim()}」の結果: ${cards.length} 件` : `全 ${cards.length} 件`}
      </p>

      {cards.length === 0 ? (
        <p style={s.empty}>該当する名刺がありません。「＋ 手入力」または「📷 取り込み」から登録できます。</p>
      ) : (
        <ul style={s.list}>
          {cards.map((card) => (
            <li key={card.id}>
              <button style={s.row} onClick={() => onOpen(card.id)}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={s.name}>{card.isFavorite ? '★ ' : ''}{fullName(card) || '(名前なし)'}</div>
                  {(card.company || card.title) && <div style={s.sub}>{[card.company, card.title].filter(Boolean).join(' / ')}</div>}
                  {card.email && <div style={s.meta}>{card.email}</div>}
                </div>
                <span style={s.meta}>›</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
