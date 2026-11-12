import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 像素级横向切割引擎（C-1/C-5/C-8）：
/// 直接裁切原图像素并无损 PNG 保存，不损失分辨率。
enum ImageCutter {
    /// 横向切一刀：yFraction ∈ (0,1)，返回（上段, 下段）
    static func cut(asset: ImageAsset, atYFraction f: CGFloat) -> (top: ImageAsset, bottom: ImageAsset)? {
        guard let img = asset.cgImage, f > 0.001, f < 0.999 else { return nil }
        let w = CGFloat(img.width)
        let h = CGFloat(img.height)
        let topH = (h * f).rounded()
        guard topH >= 1, topH <= h - 1 else { return nil }
        guard let topCG = img.cropping(to: CGRect(x: 0, y: 0, width: w, height: topH)),
              let botCG = img.cropping(to: CGRect(x: 0, y: topH, width: w, height: h - topH)),
              let topData = pngData(topCG),
              let botData = pngData(botCG) else { return nil }
        return (ImageAsset(data: topData), ImageAsset(data: botData))
    }

    /// 按高度比例切成多段（超高图片自动分页用，比例之和应为 1）
    static func split(asset: ImageAsset, heightFractions: [CGFloat]) -> [ImageAsset]? {
        guard let img = asset.cgImage, !heightFractions.isEmpty else { return nil }
        let w = CGFloat(img.width)
        let totalH = CGFloat(img.height)
        var result: [ImageAsset] = []
        var y: CGFloat = 0
        for (i, f) in heightFractions.enumerated() {
            var h = (i == heightFractions.count - 1) ? totalH - y : (totalH * f).rounded()
            h = min(h, totalH - y)
            guard h >= 1 else { return nil }
            guard let piece = img.cropping(to: CGRect(x: 0, y: y, width: w, height: h)),
                  let data = pngData(piece) else { return nil }
            result.append(ImageAsset(data: data))
            y += h
        }
        return result
    }

    /// 无损 PNG 编码
    static func pngData(_ img: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}