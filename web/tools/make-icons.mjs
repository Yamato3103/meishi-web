// MeishiVault の PWA アイコンを生成する(依存ゼロの純 Node PNG ライター)。
// 使い方: node tools/make-icons.mjs  → public/icons/{icon-192,icon-512,maskable-512}.png
//
// デザイン: フルブリードの青背景(マスカブル安全域)に、白い名刺カードと
// アバター円 + テキスト行を描く。テキストは矩形で表現(フォント非依存)。
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BLUE = [30, 102, 245];
const WHITE = [255, 255, 255];
const GRAY = [199, 199, 204];

/** size×size の RGBA バッファに名刺アイコンを描く。 */
function render(size) {
  const buf = new Uint8Array(size * size * 4);
  const put = (x, y, [r, g, b], a = 255) => {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    const i = (y * size + x) * 4;
    buf[i] = r; buf[i + 1] = g; buf[i + 2] = b; buf[i + 3] = a;
  };
  const rect = (x0, y0, w, h, color) => {
    for (let y = Math.round(y0); y < Math.round(y0 + h); y++)
      for (let x = Math.round(x0); x < Math.round(x0 + w); x++) put(x, y, color);
  };
  const roundRect = (x0, y0, w, h, r, color) => {
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const dx = Math.min(x, w - 1 - x), dy = Math.min(y, h - 1 - y);
      if (dx >= r || dy >= r || ((r - dx) ** 2 + (r - dy) ** 2) <= r * r) put(Math.round(x0 + x), Math.round(y0 + y), color);
    }
  };
  const disc = (cx, cy, r, color) => {
    for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++)
      if (x * x + y * y <= r * r) put(Math.round(cx + x), Math.round(cy + y), color);
  };

  // 背景(フルブリード=マスカブルでも欠けない)。
  rect(0, 0, size, size, BLUE);
  // 名刺カード(中央の安全域に収める)。
  const cardX = size * 0.16, cardY = size * 0.28, cardW = size * 0.68, cardH = size * 0.44;
  roundRect(cardX, cardY, cardW, cardH, size * 0.05, WHITE);
  // アバター円。
  const avatarR = cardH * 0.22;
  disc(cardX + cardW * 0.22, cardY + cardH * 0.5, avatarR, BLUE);
  // テキスト行2本。
  const lineX = cardX + cardW * 0.42, lineW = cardW * 0.42;
  roundRect(lineX, cardY + cardH * 0.38, lineW, size * 0.035, size * 0.017, GRAY);
  roundRect(lineX, cardY + cardH * 0.55, lineW * 0.7, size * 0.03, size * 0.015, GRAY);

  return buf;
}

// --- 最小 PNG エンコーダ(RGBA, 8bit) ---
const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = data.length;
  const out = Buffer.alloc(12 + len);
  out.writeUInt32BE(len, 0);
  out.write(type, 4, 'ascii');
  Buffer.from(data).copy(out, 8);
  const crcInput = out.subarray(4, 8 + len);
  out.writeUInt32BE(crc32(crcInput), 8 + len);
  return out;
}
function encodePng(size, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  // 各行の先頭にフィルタバイト0を付ける。
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    Buffer.from(rgba.subarray(y * size * 4, (y + 1) * size * 4)).copy(raw, y * (size * 4 + 1) + 1);
  }
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

const outDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'icons');
mkdirSync(outDir, { recursive: true });
for (const [name, size] of [['icon-192', 192], ['icon-512', 512], ['maskable-512', 512]]) {
  writeFileSync(join(outDir, `${name}.png`), encodePng(size, render(size)));
  console.log('✔', `${name}.png`);
}
