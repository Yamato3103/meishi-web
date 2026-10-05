/** JSON スカラ/構造の型(card.json のフィールド値 v・未知キーに使う)。 */
export type JSONValue =
  | string
  | number
  | boolean
  | null
  | JSONValue[]
  | { [key: string]: JSONValue };

/** キーを再帰的にソートした安定 JSON 文字列(iOS の .sortedKeys 相当・人間可読)。 */
export function stableStringify(value: unknown, indent = 2): string {
  return JSON.stringify(sortKeys(value), null, indent);
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      out[key] = sortKeys((value as Record<string, unknown>)[key]);
    }
    return out;
  }
  return value;
}

/** JSONValue 同士の等価判定(スカラ・入れ子とも)。 */
export function jsonEqual(a: JSONValue, b: JSONValue): boolean {
  return stableStringify(a, 0) === stableStringify(b, 0);
}

/** 履歴表示用の文字列(null は null)。 */
export function displayText(value: JSONValue): string | null {
  if (value === null) return null;
  if (typeof value === 'boolean') return value ? 'はい' : 'いいえ';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') return value;
  return null;
}
