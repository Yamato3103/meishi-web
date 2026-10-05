import { defineConfig } from 'vitest/config';

// 共有コアの単体テスト設定。純ロジック(I/O なし・JSX なし)なので Node 環境で実行し、
// プラグインは持たない。tests/**/*.test.ts を対象にする。
export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
    include: ['tests/**/*.test.ts'],
    // node:sqlite は Node 同梱の新しい組み込みモジュール。Vite の組み込み一覧に
    // 無く解決に失敗するため、外部化してそのまま Node に解決させる。
    server: { deps: { external: ['node:sqlite'] } },
  },
});
