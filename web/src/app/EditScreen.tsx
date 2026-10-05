import { useEffect, useMemo, useState } from 'react';
import type { ChangeEvent, CSSProperties } from 'react';
import type { Card, DuplicateMatch } from '../core';
import { makeCard } from '../core';
import type { OpenedDatabase } from './database';
import { s, fullName } from './ui';

/** 編集可能なテキスト欄。フォームは常に string で持ち(空は '')、保存時に null 化する。 */
type EditableKey =
  | 'familyName' | 'givenName' | 'familyNameKana' | 'givenNameKana'
  | 'company' | 'department' | 'title'
  | 'email' | 'phone' | 'mobile' | 'fax'
  | 'postalCode' | 'address' | 'url' | 'memo' | 'exchangedAt';
type Editable = Record<EditableKey, string>;

const FIELDS: { key: keyof Editable; label: string; wide?: boolean; type?: string }[] = [
  { key: 'familyName', label: '姓' }, { key: 'givenName', label: '名' },
  { key: 'familyNameKana', label: 'せい(かな)' }, { key: 'givenNameKana', label: 'めい(かな)' },
  { key: 'company', label: '会社', wide: true },
  { key: 'department', label: '部署' }, { key: 'title', label: '役職' },
  { key: 'email', label: 'メール', wide: true, type: 'email' },
  { key: 'phone', label: '電話', type: 'tel' }, { key: 'mobile', label: '携帯', type: 'tel' },
  { key: 'fax', label: 'FAX', type: 'tel' }, { key: 'postalCode', label: '郵便番号' },
  { key: 'address', label: '住所', wide: true },
  { key: 'url', label: 'ウェブ', wide: true, type: 'url' },
  { key: 'exchangedAt', label: '交換日', type: 'date' },
  { key: 'memo', label: 'メモ', wide: true },
];

function emptyEditable(): Editable {
  return {
    familyName: '', givenName: '', familyNameKana: '', givenNameKana: '',
    company: '', department: '', title: '', email: '', phone: '', mobile: '', fax: '',
    postalCode: '', address: '', url: '', memo: '', exchangedAt: '',
  };
}

function toEditable(card: Card): Editable {
  const e = emptyEditable();
  for (const f of FIELDS) e[f.key] = (card[f.key] ?? '') as string;
  return e;
}

function fromPartial(initial: Partial<Card>): Editable {
  const e = emptyEditable();
  for (const f of FIELDS) {
    const v = initial[f.key];
    if (typeof v === 'string') e[f.key] = v;
  }
  return e;
}

/**
 * 新規(cardId 未指定)/ 既存編集の共用フォーム。保存で create / update を通す。
 * `initial` を渡すと新規モードでその値を初期表示する(取り込み OCR の確認画面用)。
 */
export function EditScreen({
  db, cardId, initial, title, onSaved, onCancel,
}: {
  db: OpenedDatabase;
  cardId?: string;
  initial?: Partial<Card>;
  title?: string;
  onSaved: (id: string) => void;
  onCancel: () => void;
}) {
  const [base, setBase] = useState<Card | null>(null);
  const [form, setForm] = useState<Editable>(() => (initial ? fromPartial(initial) : emptyEditable()));
  const [favorite, setFavorite] = useState(false);
  const [busy, setBusy] = useState(false);
  // 新規保存時に重複候補が見つかったら、作成前に確認する。
  const [pending, setPending] = useState<{ draft: Card; matches: DuplicateMatch[] } | null>(null);

  useEffect(() => {
    let alive = true;
    if (!cardId) {
      setBase(null);
      setForm(initial ? fromPartial(initial) : emptyEditable());
      setFavorite(false);
      return;
    }
    db.repo.fetchOne(cardId).then((c) => {
      if (!alive || !c) return;
      setBase(c);
      setForm(toEditable(c));
      setFavorite(c.isFavorite);
    });
    return () => { alive = false; };
  }, [db, cardId, initial]);

  const canSave = useMemo(
    () => Object.values(form).some((v) => v.trim().length > 0),
    [form],
  );

  const set = (key: keyof Editable) => (e: ChangeEvent<HTMLInputElement>) =>
    setForm((prev) => ({ ...prev, [key]: e.target.value }));

  const draftFromForm = (): Card => {
    const values = Object.fromEntries(
      Object.entries(form).map(([k, v]) => [k, v.trim() ? v.trim() : null]),
    ) as Partial<Card>;
    return makeCard({ id: crypto.randomUUID(), ...values, isFavorite: favorite });
  };

  const save = async () => {
    if (!canSave || busy) return;
    setBusy(true);
    try {
      if (base) {
        const values = Object.fromEntries(
          Object.entries(form).map(([k, v]) => [k, v.trim() ? v.trim() : null]),
        ) as Partial<Card>;
        const updated: Card = { ...base, ...values, isFavorite: favorite };
        const saved = await db.repo.update(updated);
        onSaved(saved.id);
        return;
      }
      // 新規: 作成前に重複候補を確認する。
      const draft = draftFromForm();
      const matches = await db.repo.findDuplicates(draft);
      if (matches.length > 0) {
        setPending({ draft, matches });
        return;
      }
      const created = await db.repo.create(draft);
      onSaved(created.id);
    } finally {
      setBusy(false);
    }
  };

  // 候補へ統合: draft を作ってから候補(primary)に merge する。
  const mergeInto = async (match: DuplicateMatch) => {
    if (!pending || busy) return;
    setBusy(true);
    try {
      await db.repo.create(pending.draft);
      const merged = await db.repo.merge(match.card.id, pending.draft.id);
      onSaved(merged.id);
    } finally {
      setBusy(false);
    }
  };

  // 別人として登録: draft を作り、全候補と「別人」を記録する(次回以降は候補にしない)。
  const registerAsNew = async () => {
    if (!pending || busy) return;
    setBusy(true);
    try {
      const created = await db.repo.create(pending.draft);
      for (const m of pending.matches) await db.repo.markNotDuplicate(created.id, m.card.id);
      onSaved(created.id);
    } finally {
      setBusy(false);
    }
  };

  if (pending) {
    return (
      <div>
        <div style={s.topbar}>
          <button style={s.iconButton} onClick={() => setPending(null)}>← 戻る</button>
          <h1 style={s.title}>重複の確認</h1>
        </div>
        <p style={{ ...s.meta, marginTop: 0 }}>
          似ている名刺が {pending.matches.length} 件見つかりました。同じ人なら統合、別人ならそのまま登録できます。
        </p>
        {pending.matches.map((m) => (
          <div key={m.card.id} style={dupStyles.candidate}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 600 }}>{fullName(m.card) || '(名前なし)'}</div>
              {m.card.company && <div style={s.meta}>{m.card.company}</div>}
              {m.card.email && <div style={s.meta}>{m.card.email}</div>}
              <div style={{ ...s.meta, color: m.isStrong ? '#1e66f5' : '#8e8e93' }}>
                一致度 {m.isStrong ? '高' : '中'}
              </div>
            </div>
            <button style={{ ...s.ghost, ...(busy ? s.disabled : {}) }} disabled={busy} onClick={() => mergeInto(m)}>
              この人に統合
            </button>
          </div>
        ))}
        <div style={{ marginTop: '1rem' }}>
          <button
            style={{ ...s.primaryWide, ...(busy ? s.disabled : {}) }}
            disabled={busy}
            onClick={registerAsNew}
          >
            {busy ? '登録中…' : '別人として登録'}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div>
      <div style={s.topbar}>
        <button style={s.iconButton} onClick={onCancel}>← 戻る</button>
        <h1 style={s.title}>{title ?? (cardId ? '名刺を編集' : '名刺を追加')}</h1>
      </div>

      <div style={s.card}>
        <div style={s.grid2}>
          {FIELDS.map((f) => (
            <div key={f.key} style={f.wide ? { gridColumn: '1 / -1' } : undefined}>
              <div style={s.label}>{f.label}</div>
              <input
                style={s.input}
                type={f.type ?? 'text'}
                value={form[f.key]}
                onChange={set(f.key)}
                inputMode={f.type === 'tel' ? 'tel' : f.type === 'email' ? 'email' : undefined}
              />
            </div>
          ))}
          <label style={{ gridColumn: '1 / -1', display: 'flex', alignItems: 'center', gap: '0.5rem', marginTop: '0.25rem' }}>
            <input type="checkbox" checked={favorite} onChange={(e) => setFavorite(e.target.checked)} />
            お気に入り
          </label>
        </div>
      </div>

      <div style={{ marginTop: '1rem' }}>
        <button
          style={{ ...s.primaryWide, ...(!canSave || busy ? s.disabled : {}) }}
          disabled={!canSave || busy}
          onClick={save}
        >
          {busy ? '保存中…' : '保存'}
        </button>
      </div>
    </div>
  );
}

const dupStyles: Record<string, CSSProperties> = {
  candidate: { display: 'flex', alignItems: 'center', gap: '0.75rem', border: '1px solid #e5e5ea', borderRadius: 12, background: '#fafafa', padding: '0.75rem', marginTop: '0.6rem' },
};
