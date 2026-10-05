import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// 撮影・取り込んだ画像を「名刺として保存できる形」に整える。
///
/// 端検出(Vision)→ 透視補正(CoreImage)→ JPEG エンコードまで。
/// クラウドは一切使わない。矩形が見つからなければ原画像をそのまま使う(ベストエフォート)。
enum ImagePipeline {

    /// 処理結果。DB / ImageStore へ渡す確定バイト列と寸法。
    struct Processed {
        let jpegData: Data
        let width: Int
        let height: Int
        /// プレビュー表示用(補正後)。
        let image: UIImage
    }

    /// 画像を補正・エンコードする。
    static func process(_ input: UIImage, correctPerspective: Bool = true) -> Processed {
        let corrected = (correctPerspective ? correctedImage(from: input) : nil) ?? input
        let jpeg = corrected.jpegData(compressionQuality: 0.85) ?? Data()
        let width = Int(corrected.size.width * corrected.scale)
        let height = Int(corrected.size.height * corrected.scale)
        return Processed(jpegData: jpeg, width: width, height: height, image: corrected)
    }

    /// Vision で最大の矩形を検出し、CoreImage で透視補正する。見つからなければ nil。
    private static func correctedImage(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.3

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let rectangle = request.results?.first else { return nil }

        // Vision は正規化座標(原点は左下)。CIImage のピクセル座標へ変換する。
        let extent = ciImage.extent
        func denormalize(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * extent.width, y: point.y * extent.height)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = denormalize(rectangle.topLeft)
        filter.topRight = denormalize(rectangle.topRight)
        filter.bottomLeft = denormalize(rectangle.bottomLeft)
        filter.bottomRight = denormalize(rectangle.bottomRight)

        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let corrected = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: corrected)
    }
}
