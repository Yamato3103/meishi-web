import type { CSSProperties } from 'react';
import type { Card } from '../core';

/** 画面間で共有する最小スタイル。iOS 風の落ち着いた見た目。 */
export const s: Record<string, CSSProperties> = {
  app: { fontFamily: 'system-ui, sans-serif', maxWidth: 720, margin: '0 auto', padding: '0 1rem 3rem', color: '#1c1c1e' },
  topbar: { display: 'flex', alignItems: 'center', gap: '0.5rem', padding: '1rem 0', position: 'sticky', top: 0, background: '#fff', zIndex: 1 },
  title: { fontSize: '1.25rem', margin: 0, flex: 1 },
  iconButton: { border: '1px solid #e5e5ea', background: '#fff', borderRadius: 8, padding: '0.4rem 0.7rem', cursor: 'pointer', fontSize: '0.9rem' },
  primary: { border: 'none', borderRadius: 8, background: '#1e66f5', color: '#fff', padding: '0.5rem 0.9rem', cursor: 'pointer', fontSize: '0.95rem' },
  primaryWide: { width: '100%', border: 'none', borderRadius: 10, background: '#1e66f5', color: '#fff', padding: '0.7rem', cursor: 'pointer', fontSize: '1rem' },
  disabled: { background: '#b7c7ef', cursor: 'not-allowed' },
  ghost: { border: '1px solid #e5e5ea', background: '#fff', color: '#1c1c1e', borderRadius: 8, padding: '0.5rem 0.9rem', cursor: 'pointer', fontSize: '0.95rem' },
  danger: { border: '1px solid #f0c9c4', background: '#fff', color: '#c0392b', borderRadius: 8, padding: '0.5rem 0.9rem', cursor: 'pointer', fontSize: '0.95rem' },
  search: { width: '100%', padding: '0.6rem 0.7rem', border: '1px solid #d1d1d6', borderRadius: 8, fontSize: '1rem', boxSizing: 'border-box' },
  count: { color: '#8e8e93', fontSize: '0.85rem', margin: '0.75rem 0 0.25rem' },
  list: { listStyle: 'none', margin: 0, padding: 0 },
  row: { display: 'flex', alignItems: 'center', gap: '0.6rem', padding: '0.75rem 0.25rem', cursor: 'pointer', textAlign: 'left', width: '100%', background: 'none', border: 'none', borderBottom: '1px solid #eee', font: 'inherit', color: 'inherit' },
  name: { fontWeight: 600 },
  sub: { color: '#3a3a3c', fontSize: '0.9rem' },
  meta: { color: '#8e8e93', fontSize: '0.85rem' },
  empty: { color: '#8e8e93', marginTop: '1.5rem', textAlign: 'center' },
  card: { border: '1px solid #e5e5ea', borderRadius: 12, background: '#fafafa', padding: '1rem', marginTop: '0.75rem' },
  label: { color: '#8e8e93', fontSize: '0.78rem', marginBottom: '0.15rem' },
  fieldRow: { padding: '0.5rem 0', borderBottom: '1px solid #efeff4' },
  link: { color: '#1e66f5', textDecoration: 'none' },
  input: { padding: '0.5rem 0.6rem', border: '1px solid #d1d1d6', borderRadius: 8, fontSize: '0.95rem', minWidth: 0, width: '100%', boxSizing: 'border-box' },
  grid2: { display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '0.5rem' },
  chip: { display: 'inline-flex', alignItems: 'center', gap: '0.3rem', background: '#eef2fb', color: '#1e66f5', borderRadius: 999, padding: '0.2rem 0.6rem', fontSize: '0.82rem' },
  chipButton: { background: '#f2f2f7', border: '1px solid #e5e5ea', color: '#3a3a3c', borderRadius: 999, padding: '0.25rem 0.7rem', fontSize: '0.82rem', cursor: 'pointer' },
  chipButtonOn: { background: '#1e66f5', border: '1px solid #1e66f5', color: '#fff' },
  badge: { fontSize: '0.72rem', padding: '0.15rem 0.5rem', borderRadius: 999, background: '#eee', color: '#555', whiteSpace: 'nowrap' },
  badgeOk: { background: '#e5f4ea', color: '#1a7f37' },
  badgeWarn: { background: '#fdeaea', color: '#c0392b' },
  star: { border: 'none', background: 'none', cursor: 'pointer', fontSize: '1.2rem', lineHeight: 1 },
};

export function fullName(card: Card): string {
  return [card.familyName, card.givenName].filter(Boolean).join(' ');
}

export function fullNameKana(card: Card): string {
  return [card.familyNameKana, card.givenNameKana].filter(Boolean).join(' ');
}

/** URL にスキームが無ければ https:// を補う(表示用リンク)。 */
export function withScheme(url: string): string {
  return /^https?:\/\//i.test(url) ? url : `https://${url}`;
}
