#if os(macOS)
import AppKit
import PDFKit

/// 多页 PDF 打印视图。
///
/// 为什么不用 `NSPrintOperation(view: PDFView)`：
/// PDFView 作为打印视图时只会输出**当前页**（PDFKit 的老毛病），
/// 结果就是「3 页的作业只打出第 1 页」。
///
/// 正确做法：自己实现 `NSView` 的分页协议 —— `knowsPageRange` 报告总页数、
/// `rectForPage` 给出每页绘制区域，打印时 AppKit 会按页回调 `draw(_:)`，
/// 我们把对应 `PDFPage` 等比缩放画进去 → **全部页**都会进打印机。
final class PDFPrintView: NSView {
    private let document: PDFDocument

    init(document: PDFDocument) {
        self.document = document
        super.init(frame: NSRect(x: 0, y: 0, width: A4.width, height: A4.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 打印中心里显示的任务名
    override var printJobTitle: String { "PrintHelper 作业" }

    /// 总页数（location 从 1 开始）
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(1, document.pageCount))
        return true
    }

    /// 每页都用整张视图（视图尺寸 = A4，打印时由 printInfo 缩放到纸张可打印区域）
    override func rectForPage(_ page: Int) -> NSRect { bounds }

    override func draw(_ dirtyRect: NSRect) {
        // 当前正在打印第几页（1 起）：由打印运行时提供
        let index = (NSPrintOperation.current?.currentPage ?? 1) - 1
        NSColor.white.setFill()
        bounds.fill()
        guard index >= 0, index < document.pageCount,
              let page = document.page(at: index),
              let ctx = NSGraphicsContext.current?.cgContext else { return }

        let pageRect = page.bounds(for: PDFDisplayBox.cropBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return }
        let scale = min(bounds.width / pageRect.width, bounds.height / pageRect.height)
        let w = pageRect.width * scale
        let h = pageRect.height * scale
        let target = CGRect(
            x: bounds.minX + (bounds.width - w) / 2,
            y: bounds.minY + (bounds.height - h) / 2,
            width: w, height: h
        )

        ctx.saveGState()
        ctx.translateBy(x: target.minX, y: target.minY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -pageRect.minX, y: -pageRect.minY)
        page.draw(with: PDFDisplayBox.cropBox, to: ctx)
        ctx.restoreGState()
    }
}

/// macOS 打印：把整份 PDF（所有页）交给系统打印面板。
@MainActor
enum MacPrinter {
    /// 返回 NSPrintOperation（调用方需持有，runModal 是异步的）
    static func makeOperation(for data: Data) -> NSPrintOperation? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        guard let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) else { return nil }
        // 每页等比缩放到纸张可打印区域（A4 内容 → A4 纸 = 1:1）
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.jobDisposition = .spool
        info.isHorizontallyCentered = true

        let view = PDFPrintView(document: document)
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = "PrintHelper 作业"
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        return op
    }
}
#endif
