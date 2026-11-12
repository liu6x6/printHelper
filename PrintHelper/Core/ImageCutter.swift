import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 切割方向
enum CutDirection {
    case horizontal  // 水平切割线 → 上下两段
    case vertical    // 垂直切割线 → 左右两段
}

/// 像素级切割引擎（C-1/C-5/C-7/C-8）：
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

    /// 纵向切一刀：xFraction ∈ (0,1)，返回（左段, 右段）
    static func cutVertical(asset: ImageAsset, atXFraction f: CGFloat) -> (left: ImageAsset, right: ImageAsset)? {
        guard let img = asset.cgImage, f > 0.001, f < 0.999 else { return nil }
        let w = CGFloat(img.width)
        let h = CGFloat(img.height)
        let leftW = (w * f).rounded()
        guard leftW >= 1, leftW <= w - 1 else { return nil }
        guard let leftCG = img.cropping(to: CGRect(x: 0, y: 0, width: leftW, height: h)),
              let rightCG = img.cropping(to: CGRect(x: leftW, y: 0, width: w - leftW, height: h)),
              let leftData = pngData(leftCG),
              let rightData = pngData(rightCG) else { return nil }
        return (ImageAsset(data: leftData), ImageAsset(data: rightData))
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

    /// 按宽度比例纵向切成多段（N 等分用，比例之和应为 1）
    static func splitVertical(asset: ImageAsset, widthFractions: [CGFloat]) -> [ImageAsset]? {
        guard let img = asset.cgImage, !widthFractions.isEmpty else { return nil }
        let w = CGFloat(img.width)
        let h = CGFloat(img.height)
        var result: [ImageAsset] = []
        var x: CGFloat = 0
        for (i, f) in widthFractions.enumerated() {
            var cw = (i == widthFractions.count - 1) ? w - x : (w * f).rounded()
            cw = min(cw, w - x)
            guard cw >= 1 else { return nil }
            guard let piece = img.cropping(to: CGRect(x: x, y: 0, width: cw, height: h)),
                  let data = pngData(piece) else { return nil }
            result.append(ImageAsset(data: data))
            x += cw
        }
        return result
    }

    /// 顺时针旋转 90°×quarterTurns（烘焙进像素，无损 PNG）
    static func rotated(asset: ImageAsset, quarterTurns: Int) -> ImageAsset? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0, let img = asset.cgImage else { return nil }
        let w = CGFloat(img.width)
        let h = CGFloat(img.height)
        let nw = turns % 2 == 1 ? Int(h) : Int(w)
        let nh = turns % 2 == 1 ? Int(w) : Int(h)
        guard let ctx = CGContext(
            data: nil, width: nw, height: nh,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        switch turns {
        case 1:
            ctx.translateBy(x: 0, y: w)
            ctx.rotate(by: -.pi / 2)
        case 2:
            ctx.translateBy(x: w, y: h)
            ctx.rotate(by: .pi)
        default:
            ctx.translateBy(x: h, y: 0)
            ctx.rotate(by: .pi / 2)
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage(), let data = pngData(out) else { return nil }
        return ImageAsset(data: data)
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