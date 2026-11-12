import Foundation
import CoreGraphics
import Observation

/// 编辑器状态与全部编辑动作（双平台共用，不依赖 SwiftUI/UIKit/AppKit）。
/// 撤销/重做：整文档值快照（图片资源为引用共享，快照成本极低），覆盖切割（Q7）。
@MainActor
@Observable
final class EditorModel {
    private(set) var doc: PrintDocument
    var selectedID: UUID?

    private var undoStack: [PrintDocument] = []
    private var redoStack: [PrintDocument] = []
    private let undoLimit = 100

    init(layoutMode: LayoutMode) {
        doc = PrintDocument(layoutMode: layoutMode)
    }

    var pages: [[LayoutEngine.Entry]] { LayoutEngine.pages(of: doc) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedItem: ImageItem? {
        guard let id = selectedID else { return nil }
        return doc.item(id)
    }

    // MARK: - 撤销 / 重做（P-6）

    /// 在一次编辑动作开始前调用（拖拽手势开始时调用一次即可）
    func beginChange() {
        undoStack.append(doc)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(doc)
        doc = prev
        fixSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(doc)
        doc = next
        fixSelection()
    }

    private func fixSelection() {
        if let id = selectedID, doc.item(id) == nil { selectedID = nil }
    }

    // MARK: - 导入（I-1...I-6, F-4）

    func importImages(datas: [Data]) {
        var staged: [ImageItem] = []
        var stagedAssets: [UUID: ImageAsset] = [:]
        for data in datas where !data.isEmpty {
            staged.append(contentsOf: makeImportItems(data: data, into: &stagedAssets))
        }
        guard !staged.isEmpty else { return }
        beginChange()
        doc.assets.merge(stagedAssets) { _, new in new }

        switch doc.layoutMode {
        case .flow:
            doc.items.append(contentsOf: staged)
        case .free:
            let s = doc.settings
            var (page, y) = freeInsertionPoint()
            for var item in staged {
                let size = doc.size(of: item)
                if y + size.height > s.margin + s.usableHeight + LayoutEngine.epsilon,
                   y > s.margin + LayoutEngine.epsilon {
                    page += 1
                    y = s.margin
                }
                item.pageIndex = page
                item.origin = CGPoint(x: s.margin, y: y)
                doc.items.append(item)
                y += size.height + 8
            }
            LayoutEngine.normalizeFree(&doc)
        }
        selectedID = staged.last?.id
    }

    /// 生成导入项：默认铺满页宽（Q2-A）；超高图片自动按页边界切分（Q3a-C）
    private func makeImportItems(data: Data, into assets: inout [UUID: ImageAsset]) -> [ImageItem] {
        let asset = ImageAsset(data: data)
        guard asset.cgImage != nil else { return [] }
        let s = doc.settings
        let fullHeight = s.usableWidth * asset.aspectRatio

        if fullHeight <= s.usableHeight + LayoutEngine.epsilon {
            assets[asset.id] = asset
            return [ImageItem(assetID: asset.id)]
        }

        let count = max(2, Int(ceil(fullHeight / s.usableHeight)))
        let frac = s.usableHeight / fullHeight
        var fractions = Array(repeating: frac, count: count - 1)
        fractions.append(1 - frac * CGFloat(count - 1))
        if let parts = ImageCutter.split(asset: asset, heightFractions: fractions), parts.count == count {
            return parts.map { a in
                assets[a.id] = a
                return ImageItem(assetID: a.id)
            }
        }
        assets[asset.id] = asset
        return [ImageItem(assetID: asset.id)]
    }

    /// free 模式导入起点：最后一页已有内容的最下方
    private func freeInsertionPoint() -> (page: Int, y: CGFloat) {
        let s = doc.settings
        let lastPage = doc.pageCount - 1
        let maxY = doc.items
            .filter { $0.pageIndex == lastPage }
            .map { doc.frame(of: $0).maxY }
            .max() ?? s.margin
        return (lastPage, maxY > s.margin + LayoutEngine.epsilon ? maxY + 8 : s.margin)
    }

    // MARK: - 编辑（E-1...E-9）

    /// 拖拽中实时更新位置（不做规范化，手势结束时调用 finishFreeEdit）
    func setOrigin(_ id: UUID, to point: CGPoint) {
        mutate(id) { $0.origin = point }
    }

    /// 拖拽中跨页移动：同时更新所在页与页内位置
    func setPlacement(_ id: UUID, page: Int, origin: CGPoint) {
        mutate(id) {
            $0.pageIndex = max(0, page)
            $0.origin = origin
        }
    }

    func setFraction(_ id: UUID, _ fraction: CGFloat) {
        mutate(id) { $0.widthFraction = min(max(fraction, ImageItem.minFraction), 1) }
    }

    func finishFreeEdit() {
        if doc.layoutMode == .free {
            LayoutEngine.normalizeFree(&doc)
        }
    }

    func deleteSelected() {
        if let id = selectedID { delete(itemID: id) }
    }

    func delete(itemID: UUID) {
        guard let idx = doc.items.firstIndex(where: { $0.id == itemID }) else { return }
        beginChange()
        doc.items.remove(at: idx)
        cleanupAssets()
        if doc.layoutMode == .free { LayoutEngine.normalizeFree(&doc) }
        if selectedID == itemID { selectedID = nil }
    }

    func delete(at offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        beginChange()
        for i in offsets.sorted(by: >) where i < doc.items.count {
            doc.items.remove(at: i)
        }
        cleanupAssets()
        fixSelection()
    }

    func reorder(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty else { return }
        beginChange()
        let moving = offsets.sorted().map { doc.items[$0] }
        for i in offsets.sorted(by: >) { doc.items.remove(at: i) }
        var dest = destination
        for i in offsets where i < destination { dest -= 1 }
        dest = min(max(dest, 0), doc.items.count)
        doc.items.insert(contentsOf: moving, at: dest)
    }

    // MARK: - 切割（C-1...C-5）

    func cut(itemID: UUID, atFraction f: CGFloat, direction: CutDirection = .horizontal) {
        guard let idx = doc.items.firstIndex(where: { $0.id == itemID }),
              let asset = doc.assets[doc.items[idx].assetID] else { return }
        let pair: (ImageAsset, ImageAsset)?
        switch direction {
        case .horizontal:
            pair = ImageCutter.cut(asset: asset, atYFraction: f).map { ($0.top, $0.bottom) }
        case .vertical:
            pair = ImageCutter.cutVertical(asset: asset, atXFraction: f).map { ($0.left, $0.right) }
        }
        guard let (firstAsset, secondAsset) = pair else { return }
        beginChange()
        let item = doc.items[idx]
        doc.assets[firstAsset.id] = firstAsset
        doc.assets[secondAsset.id] = secondAsset

        var firstItem = item
        firstItem.assetID = firstAsset.id
        var secondItem = ImageItem(assetID: secondAsset.id)
        switch direction {
        case .horizontal:
            // 宽度不变，高度按比例缩小
            secondItem.widthFraction = item.widthFraction
        case .vertical:
            // 保持视觉缩放比例不变：两段宽度按切割比例分配
            firstItem.widthFraction = max(ImageItem.minFraction, item.widthFraction * f)
            secondItem.widthFraction = max(ImageItem.minFraction, item.widthFraction * (1 - f))
        }

        doc.items[idx] = firstItem
        switch doc.layoutMode {
        case .flow:
            doc.items.insert(secondItem, at: idx + 1)
        case .free:
            secondItem.pageIndex = item.pageIndex
            switch direction {
            case .horizontal:
                let topH = doc.size(of: firstItem).height
                secondItem.origin = CGPoint(x: item.origin.x, y: item.origin.y + topH + 4)
            case .vertical:
                let leftW = doc.size(of: firstItem).width
                secondItem.origin = CGPoint(x: item.origin.x + leftW + 4, y: item.origin.y)
            }
            doc.items.insert(secondItem, at: idx + 1)
            LayoutEngine.normalizeFree(&doc)
        }
        cleanupAssets()
        selectedID = firstItem.id
    }

    // MARK: - 旋转（E-10）

    func rotate(itemID: UUID, quarterTurns: Int = 1) {
        guard ((quarterTurns % 4) + 4) % 4 != 0,
              let idx = doc.items.firstIndex(where: { $0.id == itemID }),
              let asset = doc.assets[doc.items[idx].assetID],
              let rotated = ImageCutter.rotated(asset: asset, quarterTurns: quarterTurns) else { return }
        beginChange()
        doc.assets[rotated.id] = rotated
        doc.items[idx].assetID = rotated.id
        cleanupAssets()
        if doc.layoutMode == .free { LayoutEngine.normalizeFree(&doc) }
    }

    // MARK: - N 等分切割（C-7）

    func splitEqual(itemID: UUID, parts: Int, direction: CutDirection) {
        guard parts >= 2, parts <= 12,
              let idx = doc.items.firstIndex(where: { $0.id == itemID }),
              let asset = doc.assets[doc.items[idx].assetID] else { return }
        let fractions = Array(repeating: 1.0 / CGFloat(parts), count: parts)
        let pieces: [ImageAsset]?
        switch direction {
        case .horizontal: pieces = ImageCutter.split(asset: asset, heightFractions: fractions)
        case .vertical: pieces = ImageCutter.splitVertical(asset: asset, widthFractions: fractions)
        }
        guard let pieces, pieces.count == parts else { return }
        beginChange()
        let item = doc.items[idx]
        var newItems: [ImageItem] = []
        var cursor = item.origin
        for (i, piece) in pieces.enumerated() {
            doc.assets[piece.id] = piece
            var it = ImageItem(id: i == 0 ? item.id : UUID(), assetID: piece.id)
            it.widthFraction = direction == .vertical
                ? max(ImageItem.minFraction, item.widthFraction / CGFloat(parts))
                : item.widthFraction
            if doc.layoutMode == .free {
                it.pageIndex = item.pageIndex
                it.origin = cursor
                let sz = doc.size(of: it)
                cursor = direction == .horizontal
                    ? CGPoint(x: item.origin.x, y: cursor.y + sz.height + 4)
                    : CGPoint(x: cursor.x + sz.width + 4, y: item.origin.y)
            }
            newItems.append(it)
        }
        doc.items.replaceSubrange(idx...idx, with: newItems)
        if doc.layoutMode == .free { LayoutEngine.normalizeFree(&doc) }
        cleanupAssets()
        selectedID = newItems.first?.id
    }

    // MARK: - 工程保存 / 打开（S-1）

    func saveProject() throws -> FileWrapper {
        try ProjectFile.archive(doc)
    }

    func openProject(_ wrapper: FileWrapper) throws {
        let newDoc = try ProjectFile.load(wrapper)
        beginChange()
        doc = newDoc
        selectedID = nil
    }

    // MARK: - 导出（X-1...X-5）

    func exportPDF() -> Data? { PDFRenderer.pdfData(for: doc) }

    func exportPagePNGs() -> [Data] {
        (0..<pages.count).compactMap { PDFRenderer.pagePNG(doc: doc, pageIndex: $0) }
    }

    // MARK: - Private

    private func mutate(_ id: UUID, _ body: (inout ImageItem) -> Void) {
        guard let idx = doc.items.firstIndex(where: { $0.id == id }) else { return }
        body(&doc.items[idx])
    }

    private func cleanupAssets() {
        let used = Set(doc.items.map(\.assetID))
        doc.assets = doc.assets.filter { used.contains($0.key) }
    }
}