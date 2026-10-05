#if DEBUG
import UIKit
import MeishiKit

/// 検証・デモ用。カメラの無いシミュレータでも縦串(画像→補正→保存→DB→一覧)を
/// 通せるよう、合成した名刺画像を実パイプラインに流し込む。
/// 起動引数 `--demo-import` のときだけ AppModel から呼ばれる。
enum DemoImport {

    @MainActor
    static func run(using model: AppModel) {
        let image = syntheticBusinessCard()
        let processed = ImagePipeline.process(image, correctPerspective: false)
        // 実際に Vision で OCR し、抽出エンジンを通してフィールドを埋める(縦串の検証)。
        let extraction = VisionTextRecognizer.extract(from: processed.image)
        let draft = Card.draft(from: extraction)
        if let created = try? model.importCard(processed: processed, draft: draft) {
            model.addTag(named: "取引先", to: created)
        }
    }

    /// それらしい名刺画像をコードで描画する(実写真の代わり)。
    private static func syntheticBusinessCard() -> UIImage {
        let size = CGSize(width: 1050, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // 背景(薄いグレー)
            cg.setFillColor(UIColor.systemGray5.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // カード本体(白・角丸・影)
            let cardRect = CGRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 16)
            cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: UIColor.black.withAlphaComponent(0.2).cgColor)
            cg.setFillColor(UIColor.white.cgColor)
            cg.addPath(cardPath.cgPath)
            cg.fillPath()
            cg.setShadow(offset: .zero, blur: 0, color: nil)

            // アクセントの帯
            cg.setFillColor(UIColor.systemBlue.cgColor)
            cg.fill(CGRect(x: cardRect.minX, y: cardRect.minY, width: 10, height: cardRect.height))

            func draw(_ text: String, x: CGFloat, y: CGFloat, size fontSize: CGFloat, weight: UIFont.Weight, color: UIColor = .label) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
                    .foregroundColor: color
                ]
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }

            let left = cardRect.minX + 50
            draw("株式会社サンプル商事", x: left, y: 90, size: 34, weight: .bold)
            draw("営業本部 第一営業部  課長", x: left, y: 140, size: 20, weight: .regular, color: .secondaryLabel)
            draw("山田 太郎", x: left, y: 210, size: 52, weight: .heavy)
            draw("やまだ たろう", x: left, y: 280, size: 18, weight: .regular, color: .secondaryLabel)
            draw("〒100-0001 東京都千代田区丸の内1-2-3", x: left, y: 400, size: 18, weight: .regular, color: .secondaryLabel)
            draw("TEL 03-1234-5678 / FAX 03-1234-5679", x: left, y: 430, size: 18, weight: .regular, color: .secondaryLabel)
            draw("yamada@sample.co.jp", x: left, y: 460, size: 18, weight: .regular, color: .systemBlue)
        }
    }
}
#endif
