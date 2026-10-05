// アプリアイコン(1024x1024 PNG)を生成する簡易スクリプト。
// 実行: swift make_icon.swift <出力パス>
// CoreGraphics + ImageIO のみ(macOS で動作)。
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("context") }

let W = CGFloat(side)

// 背景グラデーション(青)
let bg = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 0.20, green: 0.52, blue: 0.98, alpha: 1),
        CGColor(red: 0.09, green: 0.30, blue: 0.82, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: W), end: CGPoint(x: W, y: 0), options: [])

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 名刺カード(白・角丸・少し傾ける)
ctx.saveGState()
ctx.translateBy(x: W / 2, y: W / 2)
ctx.rotate(by: -0.09)
ctx.translateBy(x: -W / 2, y: -W / 2)

let card = CGRect(x: 212, y: 372, width: 600, height: 340)
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 48,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.addPath(rounded(card, 40))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// アクセントの帯
ctx.setFillColor(CGColor(red: 0.13, green: 0.42, blue: 0.95, alpha: 1))
ctx.addPath(rounded(CGRect(x: card.minX + 44, y: card.minY + 44, width: 18, height: card.height - 88), 9))
ctx.fillPath()

// 氏名(太い行)
ctx.setFillColor(CGColor(red: 0.16, green: 0.20, blue: 0.28, alpha: 1))
ctx.addPath(rounded(CGRect(x: card.minX + 96, y: card.minY + 190, width: 300, height: 44), 22))
ctx.fillPath()

// 情報行(細い灰色)
ctx.setFillColor(CGColor(red: 0.72, green: 0.76, blue: 0.82, alpha: 1))
for (i, width) in [280.0, 220.0, 180.0].enumerated() {
    ctx.addPath(rounded(CGRect(x: card.minX + 96, y: card.minY + 96 + CGFloat(i) * 34, width: width, height: 20), 10))
    ctx.fillPath()
}
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.path)")
