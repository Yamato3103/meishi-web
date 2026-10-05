import { describe, it, expect } from 'vitest';
import { documentFromTesseract } from '../src/ocr/tesseractAdapter';

describe('tesseractAdapter', () => {
  it('ピクセル bbox を 0..1 正規化(左上原点)し、空行を除く', () => {
    const doc = documentFromTesseract({
      lines: [
        { text: '株式会社サンプル\n', confidence: 92, bbox: { x0: 50, y0: 60, x1: 500, y1: 120 } },
        { text: '   ', confidence: 10, bbox: { x0: 0, y0: 0, x1: 1, y1: 1 } },
      ],
    }, 1000, 600);

    expect(doc.lines).toHaveLength(1);
    const line = doc.lines[0];
    expect(line.text).toBe('株式会社サンプル');
    expect(line.bbox).toEqual({ x: 0.05, y: 0.1, w: 0.45, h: 0.1 });
    expect(line.confidence).toBeCloseTo(0.92);
    expect(doc.imageSize).toEqual({ width: 1000, height: 600 });
    expect(doc.source).toBe('tesseract');
  });
});
