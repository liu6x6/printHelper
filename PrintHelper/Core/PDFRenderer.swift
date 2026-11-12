import Foundation
import CoreGraphics
import ImageIO

/// 导出渲染：标准 A4 PDF（X-1/X-2）与每页 PNG（X-3）。
/// 默认按 300 DPI 重采样（X-5），足够打印清晰且文件小。
enum PDFRenderer {
    static let exportDPI: CGFloat = 300

    // MARK: - PDF

    static func pdfData(for doc: PrintDocument) -> Data? {
        let pages = LayoutEngine.pages(of: doc)
        let out = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: A4.width, height: A4.height)
        guard let consumer = CGDataConsumer(data: out as CFMutableData) else { return nil }
        let ctx = withUnsafePointer(to: &mediaBox) { box in
            CGContext(consumer: consumer, mediaBox: box, nil)
        }
        guard let ctx else { return nil }

        for entries in pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: A4.width, height: A4.height))
            draw(entries: entries, of: doc, in: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return out as Data
    }

    // MARK: - 每页 PNG

    static func pagePNG(doc: PrintDocument, pageIndex: Int, dpi: CGFloat = exportDPI) -> Data? {
        let pages = LayoutEngine.pages(of: doc)
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        let scale = dpi / 72
        let w = Int(A4.width * scale)
        let h = Int(A4.height * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: A4.width, height: A4.height))
        draw(entries: pages[pageIndex], of: doc, in: ctx)
        guard let img = ctx.makeImage() else { return nil }
        return ImageCutter.pngData(img)
    }

    // MARK: - 绘制

    /// 绘制一页的所有图片。
    /// 注意：上下文保持 Quartz 默认坐标系（y 向上），逐张把页面坐标（左上原点）
    /// 换算为 PDF 坐标。不能整体翻转上下文，否则 CGContext.draw 会把图片上下镜像。
    private static func draw(entries: [LayoutEngine.Entry], of doc: PrintDocument, in ctx: CGContext) {
        ctx.interpolationQuality = .high
        for entry in entries {
            guard let asset = doc.assets[entry.item.assetID],
                  let raw = asset.cgImage,
                  entry.frame.width > 0, entry.frame.height > 0 else { continue }
            let targetPixelW = entry.frame.width / 72 * exportDPI
            let img = downsample(raw, maxPixelWidth: targetPixelW)
            let f = entry.frame
            let drawRect = CGRect(x: f.minX, y: A4.height - f.maxY, width: f.width, height: f.height)
            ctx.draw(img, in: drawRect)
        }
    }

    /// 只缩不放：像素宽超过目标才重采样
    private static func downsample(_ img: CGImage, maxPixelWidth: CGFloat) -> CGImage {
        guard CGFloat(img.width) > maxPixelWidth, maxPixelWidth >= 1 else { return img }
        let scale = maxPixelWidth / CGFloat(img.width)
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
        return ctx.makeImage() ?? img
    }
}