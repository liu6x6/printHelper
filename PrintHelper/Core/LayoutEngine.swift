import Foundation
import CoreGraphics

/// 排版引擎：
/// - free（macOS）：自由摆放；不允许跨页，超出整张挪到下一页（Q3-C）
/// - flow（iOS）：单列流式；放不下整张换页（Q5-B），水平居中
enum LayoutEngine {
    struct Entry {
        let item: ImageItem
        let frame: CGRect
    }

    static let flowSpacing: CGFloat = 8
    static let epsilon: CGFloat = 0.5

    static func pages(of doc: PrintDocument) -> [[Entry]] {
        switch doc.layoutMode {
        case .free: freePages(doc)
        case .flow: flowPages(doc)
        }
    }

    // MARK: - Free（macOS）

    static func freePages(_ doc: PrintDocument) -> [[Entry]] {
        var pages: [[Entry]] = Array(repeating: [], count: max(1, doc.pageCount))
        for item in doc.items {
            let idx = min(max(0, item.pageIndex), pages.count - 1)
            pages[idx].append(Entry(item: item, frame: doc.frame(of: item)))
        }
        return pages
    }

    /// 规范化 free 布局：
    /// 1. 比例夹在 [minFraction, 1]，且保证高度不超过一页可用高度
    /// 2. 水平夹在内容区内；垂直不低于上边距
    /// 3. 底边超出内容区 → 整张挪到下一页顶部（可级联），页数自动扩展
    static func normalizeFree(_ doc: inout PrintDocument) {
        let s = doc.settings

        for i in doc.items.indices {
            guard let a = doc.assets[doc.items[i].assetID] else { continue }
            let aspect = a.aspectRatio
            let maxFracByHeight = aspect > 0 ? s.usableHeight / (s.usableWidth * aspect) : 1
            let f = doc.items[i].widthFraction
            doc.items[i].widthFraction = min(max(f, ImageItem.minFraction), min(1, maxFracByHeight))
        }

        let order = doc.items.indices.sorted {
            (doc.items[$0].pageIndex, doc.items[$0].origin.y) < (doc.items[$1].pageIndex, doc.items[$1].origin.y)
        }
        for i in order {
            var item = doc.items[i]
            let size = doc.size(of: item)
            item.origin.x = min(max(item.origin.x, s.margin), s.margin + s.usableWidth - size.width)
            item.origin.y = max(item.origin.y, s.margin)
            var guardCount = 0
            while item.origin.y + size.height > s.margin + s.usableHeight + epsilon, guardCount < 1000 {
                item.pageIndex += 1
                item.origin.y = s.margin
                guardCount += 1
            }
            doc.items[i] = item
        }
        doc.pageCount = max(1, (doc.items.map(\.pageIndex).max() ?? 0) + 1)
    }

    // MARK: - Flow（iOS）

    static func flowPages(_ doc: PrintDocument) -> [[Entry]] {
        let s = doc.settings
        var pages: [[Entry]] = [[]]
        var y = s.margin
        for item in doc.items {
            let size = doc.size(of: item)
            guard size.width > 0, size.height > 0 else { continue }
            if y + size.height > s.margin + s.usableHeight + epsilon, y > s.margin + epsilon {
                pages.append([])
                y = s.margin
            }
            let x = s.margin + (s.usableWidth - size.width) / 2
            pages[pages.count - 1].append(
                Entry(item: item, frame: CGRect(x: x, y: y, width: size.width, height: size.height))
            )
            y += size.height + flowSpacing
        }
        return pages
    }
}