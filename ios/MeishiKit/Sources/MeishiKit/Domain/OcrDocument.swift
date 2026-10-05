import Foundation

/// フィールド抽出エンジンの共通入力。
///
/// iOS(Vision)/ Web(Tesseract)は OCR 結果をこの形へ整形してからエンジンに渡す。
/// 詳細は spec/schema/ocr-document.schema.json と整合。
public struct OcrDocument: Codable, Sendable {

    public struct ImageSize: Codable, Sendable {
        public var width: Double
        public var height: Double
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// 画像左上原点、0..1 正規化のバウンディングボックス。
    public struct BBox: Codable, Sendable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double
        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    public struct Line: Codable, Sendable {
        public var text: String
        public var confidence: Double?
        public var bbox: BBox
        public init(text: String, confidence: Double? = nil, bbox: BBox) {
            self.text = text
            self.confidence = confidence
            self.bbox = bbox
        }
    }

    public var imageSize: ImageSize
    public var source: String?
    public var lines: [Line]

    public init(imageSize: ImageSize, source: String? = nil, lines: [Line]) {
        self.imageSize = imageSize
        self.source = source
        self.lines = lines
    }
}
