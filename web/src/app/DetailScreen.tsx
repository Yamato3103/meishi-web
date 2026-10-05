import { useCallback, useEffect, useRef, useState } from 'react';
import type { Card } from '../core';
import type { OpenedDatabase } from './database';
import type { Tag, FieldConflictRecord } from '../db';
import { s, fullName, fullNameKana, withScheme } from './ui';

/** card.json のフィールド名 → 日本語ラベル(競合履歴の表示用)。 */
const FIELD_LABELS: Record<string, string> = {
  family_name: '姓', given_name: '名', family_name_kana: 'せい(かな)', given_name_kana: 'めい(かな)',
  company: '会社', department: '部署', title: '役職', phone: '電話', mobile: '携帯', fax: 'FAX',
  email: 'メール', postal_code: '郵便番号', address: '住所', website: 'ウェブ', memo: 'メモ',
  is_favorite: 'お気に入り', exchanged_at: '交換日',
};

/** 名刺詳細。連絡先アクション・タグ編集・お気に入り・編集/削除。 */
export function DetailScreen({
  db, cardId, onEdit, onBack, onDeleted,
}: {
  db: OpenedDatabase;
  cardId: string;
  onEdit: (id: string) => void;
  onBack: () => void;
  onDeleted: () => void;
}) {
  const [card, setCard] = useState<Card | null>(null);
  const [tags, setTags] = useState<Tag[]>([]);
  const [allTags, setAllTags] = useState<Tag[]>([]);
  const [newTag, setNewTag] = useState('');
  const [editingTags, setEditingTags] = useState(false);
  const [imageUrls, setImageUrls] = useState<string[]>([]);
  const [conflicts, setConflicts] = useState<FieldConflictRecord[]>([]);
  const urlsRef = useRef<string[]>([]);

  const load = useCallback(async () => {
    const [c, t, all, imgs, conf] = await Promise.all([
      db.repo.fetchOne(cardId),
      db.repo.tags(cardId),
      db.repo.allTags(),
      db.repo.fetchImages(cardId),
      db.repo.conflicts(cardId),
    ]);
    setCard(c ?? null);
    setTags(t);
    setAllTags(all);
    setConflicts(conf);

    // 画像の実体を OPFS から読み、表示用の Blob URL を作る(実体が無ければスキップ)。
    const urls: string[] = [];
    for (const img of imgs) {
      try {
        const bytes = await db.imageStore.read(img.relativePath);
        const type = img.relativePath.endsWith('.png') ? 'image/png' : 'image/jpeg';
        urls.push(URL.createObjectURL(new Blob([bytes.slice()], { type })));
      } catch { /* 実体なし(同期メタのみ等)は無視 */ }
    }
    urlsRef.current.forEach((u) => URL.revokeObjectURL(u));
    urlsRef.current = urls;
    setImageUrls(urls);
  }, [db, cardId]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => () => { urlsRef.current.forEach((u) => URL.revokeObjectURL(u)); }, []);

  if (!card) {
    return (
      <div>
        <div style={s.topbar}><button style={s.iconButton} onClick={onBack}>← 戻る</button></div>
        <p style={s.empty}>読み込み中…</p>
      </div>
    );
  }

  const assignedIds = new Set(tags.map((t) => t.id));

  const toggleFavorite = async () => {
    const saved = await db.repo.update({ ...card, isFavorite: !card.isFavorite });
    setCard(saved);
  };

  const toggleTag = async (tag: Tag) => {
    if (assignedIds.has(tag.id)) await db.repo.removeTag(tag.id, cardId);
    else await db.repo.addTag(tag.id, cardId);
    await load();
  };

  const addNewTag = async () => {
    const name = newTag.trim();
    if (!name) return;
    const tag = await db.repo.createOrGetTag(name);
    await db.repo.addTag(tag.id, cardId);
    setNewTag('');
    await load();
  };

  const remove = async () => {
    await db.repo.softDelete(cardId);
    onDeleted();
  };

  const dismissConflict = async (id: string) => {
    await db.repo.dismissConflict(id);
    await load();
  };

  return (
    <div>
      <div style={s.topbar}>
        <button style={s.iconButton} onClick={onBack}>← 戻る</button>
        <h1 style={s.title}>{fullName(card) || '(名前なし)'}</h1>
        <button style={s.star} onClick={toggleFavorite} aria-label="お気に入り">{card.isFavorite ? '★' : '☆'}</button>
        <button style={s.primary} onClick={() => onEdit(cardId)}>編集</button>
      </div>

      {imageUrls.length > 0 && (
        <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginTop: '0.75rem' }}>
          {imageUrls.map((url) => (
            <img key={url} src={url} alt="名刺画像" style={imageStyle} />
          ))}
        </div>
      )}

      <div style={s.card}>
        {fullNameKana(card) && <Field label="ふりがな" value={fullNameKana(card)} />}
        {(card.company || card.department || card.title) && (
          <Field label="所属" value={[card.company, card.department, card.title].filter(Boolean).join(' / ')} />
        )}
        {card.email && <Field label="メール" value={card.email} href={`mailto:${card.email}`} />}
        {card.phone && <Field label="電話" value={card.phone} href={`tel:${card.phone}`} />}
        {card.mobile && <Field label="携帯" value={card.mobile} href={`tel:${card.mobile}`} />}
        {card.fax && <Field label="FAX" value={card.fax} />}
        {(card.postalCode || card.address) && (
          <Field label="住所" value={[card.postalCode ? `〒${card.postalCode}` : null, card.address].filter(Boolean).join(' ')} />
        )}
        {card.url && <Field label="ウェブ" value={card.url} href={withScheme(card.url)} external />}
        {card.exchangedAt && <Field label="交換日" value={card.exchangedAt} />}
        {card.memo && <Field label="メモ" value={card.memo} />}
      </div>

      <div style={{ ...s.card }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
          <div style={{ ...s.label, margin: 0, flex: 1 }}>タグ</div>
          <button style={s.chipButton} onClick={() => setEditingTags((v) => !v)}>{editingTags ? '完了' : '＋ 編集'}</button>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.4rem' }}>
          {tags.length === 0 && !editingTags && <span style={s.meta}>タグなし</span>}
          {!editingTags && tags.map((t) => <span key={t.id} style={s.chip}>#{t.name}</span>)}
          {editingTags && allTags.map((t) => (
            <button
              key={t.id}
              style={{ ...s.chipButton, ...(assignedIds.has(t.id) ? s.chipButtonOn : {}) }}
              onClick={() => toggleTag(t)}
            >
              {assignedIds.has(t.id) ? '✓ ' : ''}#{t.name}
            </button>
          ))}
        </div>
        {editingTags && (
          <div style={{ display: 'flex', gap: '0.4rem', marginTop: '0.6rem' }}>
            <input
              style={s.input}
              placeholder="新しいタグ"
              value={newTag}
              onChange={(e) => setNewTag(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') void addNewTag(); }}
            />
            <button style={{ ...s.primary, ...(newTag.trim() ? {} : s.disabled) }} disabled={!newTag.trim()} onClick={addNewTag}>追加</button>
          </div>
        )}
      </div>

      {conflicts.length > 0 && (
        <div style={{ ...s.card }}>
          <div style={{ ...s.label, marginBottom: '0.5rem' }}>編集履歴(自動解決)</div>
          <p style={{ ...s.meta, marginTop: 0 }}>
            他の端末との同期でフィールドが競合し、新しい方を採用しました。捨てられた値を確認できます。
          </p>
          {conflicts.map((c) => (
            <div key={c.id} style={s.fieldRow}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: '0.5rem' }}>
                <div style={{ ...s.label, margin: 0 }}>{FIELD_LABELS[c.field] ?? c.field}</div>
                <div style={{ ...s.meta, flex: 1 }}>{new Date(c.createdAt).toLocaleString()}</div>
                <button style={s.chipButton} onClick={() => void dismissConflict(c.id)}>破棄</button>
              </div>
              <div style={{ fontSize: '0.9rem' }}>
                <span style={{ textDecoration: 'line-through', color: '#8e8e93' }}>{c.losingValue ?? '(空)'}</span>
                {' → '}
                <span>{c.winningValue ?? '(空)'}</span>
              </div>
            </div>
          ))}
        </div>
      )}

      <div style={{ marginTop: '1rem' }}>
        <button style={s.danger} onClick={remove}>削除(最近削除へ)</button>
      </div>
    </div>
  );
}

const imageStyle = { maxWidth: '100%', maxHeight: 220, objectFit: 'contain', borderRadius: 10, border: '1px solid #e5e5ea' } as const;

function Field({ label, value, href, external }: { label: string; value: string; href?: string; external?: boolean }) {
  return (
    <div style={s.fieldRow}>
      <div style={s.label}>{label}</div>
      {href
        ? <a style={s.link} href={href} target={external ? '_blank' : undefined} rel={external ? 'noreferrer' : undefined}>{value}</a>
        : <span>{value}</span>}
    </div>
  );
}
