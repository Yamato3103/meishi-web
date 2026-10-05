import UIKit
import Vision
import MeishiKit

/// Vision で名刺画像の文字を認識し、抽出エンジンの共通入力 `OcrDocument` に整形する。
/// クラウドは使わない(オンデバイス)。
enum VisionTextRecognizer {

    /// 画像を OCR して OcrDocument を返す。認識できなければ空の lines。
    static func recognize(_ image: UIImage) -> OcrDocument {
        let size = OcrDocument.ImageSize(
            width: Double(image.size.width * image.scale),
            height: Double(image.size.height * image.scale)
        )
        guard let cgImage = image.cgImage else {
            return OcrDocument(imageSize: size, source: "vision", lines: [])
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ja-JP", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        let observations = request.results ?? []
        let lines: [OcrDocument.Line] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision の boundingBox は正規化・原点左下。上下反転して左上原点に合わせる。
            let box = observation.boundingBox
            let bbox = OcrDocument.BBox(
                x: Double(box.origin.x),
                y: Double(1.0 - box.origin.y - box.size.height),
                w: Double(box.size.width),
                h: Double(box.size.height)
            )
            return OcrDocument.Line(text: candidate.string, confidence: Double(candidate.confidence), bbox: bbox)
        }

        return OcrDocument(imageSize: size, source: "vision", lines: lines)
    }

    /// OCR → フィールド抽出までを一括で行う。
    static func extract(from image: UIImage) -> ExtractionResult {
        FieldExtractor.extract(from: recognize(image))
    }
}
