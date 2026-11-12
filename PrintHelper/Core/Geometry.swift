import CoreGraphics

/// A4 几何常量与页面设置。
/// 坐标约定：页面坐标系原点在左上角，y 向下（与 SwiftUI 一致）；导出 PDF 时再翻转。
enum A4 {
    static let width: CGFloat = 595.28   // 210mm
    static let height: CGFloat = 841.89  // 297mm
    static let mmToPt: CGFloat = 72.0 / 25.4
}

struct PageSettings: Equatable {
    /// 四边统一边距，默认 10mm
    var margin: CGFloat = 10 * A4.mmToPt

    var usableWidth: CGFloat { A4.width - 2 * margin }
    var usableHeight: CGFloat { A4.height - 2 * margin }
    var contentRect: CGRect {
        CGRect(x: margin, y: margin, width: usableWidth, height: usableHeight)
    }
}