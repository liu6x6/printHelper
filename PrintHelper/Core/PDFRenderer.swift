import Foundation
import CoreGraphics
import ImageIO

/// 导出渲染：标准 A4 PDF（X-1/X-2）与每页 / 长图 PNG·JPG（X-3）。
/// 默认按 300 DPI 重采样（X-5），足够打印清晰且文件小。
/// 所有方法都不依赖 UI，可在后台线程调用（导出时不卡界面）。
enum PDFRenderer {
    static let exportDPI: CGFloat = 300
    /// 长图默认 150 DPI：页数多时控制内存（A4×N 张拼接很容易超 32767px 上限）
    static let longImageDPI: CGFloat = 150
    static let jpegQuality: CGFloat = 0.9

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
        let data = out as Data
        return data.isEmpty ? nil : data
    }

    /// PDF 页数（用于打印任务名 / UI 提示）
    static func pageCount(of doc: PrintDocument) -> Int {
        LayoutEngine.pages(of: doc).count
    }

    // MARK: - 位图（每页 / 长图，PNG 或 JPG）

    static func pagePNG(doc: PrintDocument, pageIndex: Int, dpi: CGFloat = exportDPI) -> Data? {
        guard let img = pageImage(doc: doc, pageIndex: pageIndex, dpi: dpi) else { return nil }
        return ImageCutter.pngData(img)
    }

    static func pageJPEG(doc: PrintDocument, pageIndex: Int, dpi: CGFloat = exportDPI,
                         quality: CGFloat = jpegQuality) -> Data? {
        guard let img = pageImage(doc: doc, pageIndex: pageIndex, dpi: dpi) else { return nil }
        return ImageCutter.jpegData(img, quality: quality)
    }

    static func longImagePNG(doc: PrintDocument, dpi: CGFloat = longImageDPI) -> Data? {
        guard let img = longImage(doc: doc, dpi: dpi) else { return nil }
        return ImageCutter.pngData(img)
    }

    static func longImageJPEG(doc: PrintDocument, dpi: CGFloat = longImageDPI,
                              quality: CGFloat = jpegQuality) -> Data? {
        guard let img = longImage(doc: doc, dpi: dpi) else { return nil }
        return ImageCutter.jpegData(img, quality: quality)
    }

    /// 单页位图
    static func pageImage(doc: PrintDocument, pageIndex: Int, dpi: CGFloat = exportDPI) -> CGImage? {
        let pages = LayoutEngine.pages(of: doc)
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        let scale = dpi / 72
        guard let ctx = makeContext(width: Int(A4.width * scale), height: Int(A4.height * scale)) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: A4.width, height: A4.height))
        draw(entries: pages[pageIndex], of: doc, in: ctx)
        return ctx.makeImage()
    }

    /// 所有页纵向拼接成一张长图
    static func longImage(doc: PrintDocument, dpi: CGFloat = longImageDPI) -> CGImage? {
        let pages = LayoutEngine.pages(of: doc)
        guard !pages.isEmpty else { return nil }
        let scale = dpi / 72
        let w = Int(A4.width * scale)
        let pageH = Int(A4.height * scale)
        let totalH = pageH * pages.count
        guard totalH <= 32_767 else { return nil }  // CG 位图高度上限
        guard let ctx = makeContext(width: w, height: totalH) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        for (i, entries) in pages.enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(pages.count - 1 - i) * A4.height)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: A4.width, height: A4.height))
            draw(entries: entries, of: doc, in: ctx)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    // MARK: - 绘制

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

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
        guard let ctx = makeContext(width: w, height: h) else { return img }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }
}
