import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// アプリのビルド/開発サーバ設定。テスト設定は vitest.config.ts に分離している
// (vitest/config と @vitejs/plugin-react の vite 型の二重化を避けるため)。
// https://vite.dev/config/
export default defineConfig({
  // GitHub Pages のプロジェクトページ等、ルート以外の配下にデプロイする場合は
  // VITE_BASE_PATH="/リポジトリ名/" のように設定する(既定はルート配信)。
  base: process.env.VITE_BASE_PATH || '/',
  plugins: [react()],
  // @sqlite.org/sqlite-wasm は wasm を実行時に fetch し、esbuild の事前バンドルと
  // 相性が悪いため最適化から除外する(OPFS SAHPool はメインスレッドで動くので
  // COOP/COEP ヘッダは不要)。
  optimizeDeps: { exclude: ['@sqlite.org/sqlite-wasm'] },
});
