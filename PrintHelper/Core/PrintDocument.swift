import Foundation
import CoreGraphics

/// 画布上的一张图片（或切割后的一段）。
struct ImageItem: Identifiable, Equatable {
    static let minFraction: CGFloat = 0.05

    let id: UUID
    var assetID: UUID
    /// 宽度比例，基准 = 页面可用宽度（0.05...1.0）
    var widthFraction: CGFloat = 1.0
    /// free 模式：所在页（0 起）。flow 模式忽略，由排版引擎计算。
    var pageIndex: Int = 0
    /// free 模式：左上角位置（页面 pt 坐标）。flow 模式忽略。
    var origin: CGPoint = .zero

    init(id: UUID = UUID(), assetID: UUID) {
        self.id = id
        self.assetID = assetID
    }
}

enum LayoutMode: Equatable {
    case free  // macOS：自由摆放，不跨页
    case flow  // iOS：单列流式
}

/// 整个文档的值类型模型：快照即撤销单元。
struct PrintDocument: Equatable {
    var layoutMode: LayoutMode
    var settings = PageSettings()
    var assets: [UUID: ImageAsset] = [:]
    var items: [ImageItem] = []
    /// free 模式的显式页数；flow 模式由排版引擎计算
    var pageCount = 1

    init(layoutMode: LayoutMode) {
        self.layoutMode = layoutMode
    }

    func asset(for item: ImageItem) -> ImageAsset? { assets[item.assetID] }

    /// 图片在页面上的尺寸（pt）
    func size(of item: ImageItem) -> CGSize {
        guard let a = assets[item.assetID] else { return .zero }
        let w = settings.usableWidth * item.widthFraction
        return CGSize(width: w, height: w * a.aspectRatio)
    }

    /// free 模式的页面内 frame
    func frame(of item: ImageItem) -> CGRect {
        CGRect(origin: item.origin, size: size(of: item))
    }

    func item(_ id: UUID) -> ImageItem? { items.first { $0.id == id } }
}