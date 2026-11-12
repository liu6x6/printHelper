import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 一份原始图片数据（导入的原图，或切割后无损 PNG）。
/// 引用类型：文档快照（撤销）之间共享，拷贝成本极低。
final class ImageAsset: Identifiable, Equatable {
    let id: UUID
    let data: Data

    private var cachedImage: CGImage?
    private var cachedThumb: CGImage?

    init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }

    var cgImage: CGImage? {
        if let cachedImage { return cachedImage }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cachedImage = img
        return img
    }

    var pixelSize: CGSize {
        guard let img = cgImage else { return .zero }
        return CGSize(width: img.width, height: img.height)
    }

    /// 高 / 宽
    var aspectRatio: CGFloat {
        let s = pixelSize
        return s.width > 0 ? s.height / s.width : 1
    }

    /// 屏幕显示用缩略图（限制最长边 ~1400px，避免 50+ 张大图卡顿）
    var thumbnail: CGImage? {
        if let cachedThumb { return cachedThumb }
        guard let img = cgImage else { return nil }
        let maxPixel: CGFloat = 1400
        guard CGFloat(img.width) > maxPixel else {
            cachedThumb = img
            return img
        }
        let scale = maxPixel / CGFloat(img.width)
        let w = max(1, Int(CGFloat(img.width) * scale))
        let h = max(1, Int(CGFloat(img.height) * scale))
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        cachedThumb = ctx.makeImage() ?? img
        return cachedThumb
    }

    static func == (lhs: ImageAsset, rhs: ImageAsset) -> Bool { lhs === rhs }
}