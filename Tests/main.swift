// 核心逻辑冒烟测试（不属于 App target，用 swiftc 单独编译运行）
// swiftc PrintHelper/Core/*.swift Tests/core_main.swift -o /tmp/ph_core_test && /tmp/ph_core_test
import Foundation
import CoreGraphics
import ImageIO
import PDFKit

func makeImage(w: Int, h: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ImageCutter.pngData(ctx.makeImage()!)!
}

var failures = 0
func check(_ cond: Bool, _ name: String) {
    print((cond ? "PASS" : "FAIL") + "  " + name)
    if !cond { failures += 1 }
}

await MainActor.run {
    let s = PageSettings()
    let usableH = s.usableHeight
    let usableW = s.usableWidth

    // ---- 1. 用户场景：3 张 60% 大小的图 → 3 页；各切一半 → 2 页 ----
    let m = EditorModel(layoutMode: .flow)
    // 高宽比 = 可用高/可用宽：缩放到 60% 宽时，高度恰为 0.6 × 可用高
    let h60 = Int(usableH / usableW * 1000)
    let img = makeImage(w: 1000, h: h60, r: 0.9, g: 0.9, b: 0.9)
    m.importImages(datas: [img, img, img])
    for item in m.doc.items { m.setFraction(item.id, 0.6) }
    check(m.pages.count == 3, "流式：3 张 60% 图占 3 页（实际 \(m.pages.count)）")
    for item in m.doc.items { m.cut(itemID: item.id, atFraction: 0.5) }
    check(m.doc.items.count == 6, "切割后共 6 段（实际 \(m.doc.items.count)）")
    check(m.pages.count == 2, "切割后省纸：2 页（实际 \(m.pages.count)）")

    // ---- 2. 切割像素无损 ----
    let a = ImageAsset(data: makeImage(w: 800, h: 600, r: 1, g: 0, b: 0))
    let parts = ImageCutter.cut(asset: a, atYFraction: 0.4)!
    check(parts.top.pixelSize == CGSize(width: 800, height: 240), "上段 800x240（实际 \(parts.top.pixelSize)）")
    check(parts.bottom.pixelSize == CGSize(width: 800, height: 360), "下段 800x360（实际 \(parts.bottom.pixelSize)）")

    // ---- 3. 超高图片自动切分（Q3a-C）----
    let tall = EditorModel(layoutMode: .flow)
    tall.importImages(datas: [makeImage(w: 1000, h: 5000, r: 0, g: 0.5, b: 1)])
    let expected = Int(ceil(usableW * 5.0 / usableH))
    check(tall.doc.items.count == expected, "超高图自动切成 \(expected) 段（实际 \(tall.doc.items.count)）")
    let allFit = tall.doc.items.allSatisfy { tall.doc.size(of: $0).height <= usableH + 0.5 }
    check(allFit, "每段高度都不超过一页")
    let pixelSum = tall.doc.items.compactMap { tall.doc.assets[$0.assetID]?.pixelSize.height }.reduce(0, +)
    check(pixelSum == 5000, "切分像素总高无损 = 5000（实际 \(pixelSum)）")
    check(tall.pages.count == expected, "超高图占 \(expected) 页（实际 \(tall.pages.count)）")

    // ---- 4. free 模式：不跨页，整张挪到下一页（Q3-C）----
    let fm = EditorModel(layoutMode: .free)
    fm.importImages(datas: [makeImage(w: 600, h: 400, r: 0, g: 1, b: 0)])
    let id = fm.doc.items[0].id
    check(fm.doc.items[0].pageIndex == 0 && fm.doc.pageCount == 1, "free：初始 1 页")
    fm.beginChange()
    fm.setOrigin(id, to: CGPoint(x: 30, y: 800))
    fm.finishFreeEdit()
    check(fm.doc.items[0].pageIndex == 1, "free：拖出页底 → 整张到第 2 页（实际页 \(fm.doc.items[0].pageIndex + 1)）")
    check(fm.doc.pageCount == 2, "free：自动扩页（实际 \(fm.doc.pageCount)）")
    check(fm.doc.items[0].origin.y == s.margin, "free：挪页后贴顶边距")

    // ---- 5. 撤销/重做覆盖切割 ----
    let um = EditorModel(layoutMode: .flow)
    um.importImages(datas: [makeImage(w: 800, h: 600, r: 0.2, g: 0.2, b: 0.8)])
    let origID = um.doc.items[0].id
    um.cut(itemID: origID, atFraction: 0.5)
    check(um.doc.items.count == 2, "切割后 2 段")
    um.undo()
    check(um.doc.items.count == 1 && um.doc.item(origID) != nil, "撤销恢复为 1 张原图")
    um.redo()
    check(um.doc.items.count == 2, "重做恢复切割")

    // ---- 6. PDF / PNG 导出 ----
    if let pdf = tall.exportPDF() {
        check(pdf.prefix(4) == Data("%PDF".utf8), "PDF 文件头正确")
        let doc = PDFDocument(data: pdf)
        check(doc?.pageCount == expected, "PDF 页数 = \(expected)（实际 \(doc?.pageCount ?? -1)）")
        if let page = doc?.page(at: 0) {
            let box = page.bounds(for: .mediaBox)
            check(abs(box.width - 595.28) < 1 && abs(box.height - 841.89) < 1, "PDF 页面为标准 A4（\(box)）")
        }
    } else {
        check(false, "PDF 导出失败")
    }
    if let png = tall.exportPagePNGs().first,
       let src = CGImageSourceCreateWithData(png as CFData, nil),
       let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        check(cg.width == 2480 && cg.height == 3507, "每页 PNG 为 300DPI A4（实际 \(cg.width)x\(cg.height)）")
    } else {
        check(false, "PNG 导出失败")
    }

    // ---- 7. 空文档导出 1 页空白 A4 ----
    let empty = EditorModel(layoutMode: .free)
    let emptyPDF = empty.exportPDF().flatMap { PDFDocument(data: $0) }
    check(emptyPDF?.pageCount == 1, "空文档导出 1 页")

    // ---- 8. 调序与批量删除 ----
    let rm = EditorModel(layoutMode: .flow)
    rm.importImages(datas: [
        makeImage(w: 100, h: 100, r: 1, g: 0, b: 0),
        makeImage(w: 100, h: 100, r: 0, g: 1, b: 0),
        makeImage(w: 100, h: 100, r: 0, g: 0, b: 1),
    ])
    let ids = rm.doc.items.map(\.id)
    rm.reorder(from: IndexSet(integer: 0), to: 3)
    check(rm.doc.items.map(\.id) == [ids[1], ids[2], ids[0]], "调序：第 1 张移到最后")
    rm.delete(at: IndexSet([0, 2]))
    check(rm.doc.items.map(\.id) == [ids[2]], "批量删除")
    check(rm.doc.assets.count == 1, "删除后无孤儿图片资源")
    rm.undo()
    check(rm.doc.items.count == 3, "撤销批量删除")

    // ---- 9. 回归：free 模式跨页向上拖回（bug：第 2 页拖不回第 1 页）----
    let pm = EditorModel(layoutMode: .free)
    pm.importImages(datas: [
        makeImage(w: 600, h: 400, r: 1, g: 0, b: 0),
        makeImage(w: 600, h: 400, r: 0, g: 0, b: 1),
    ])
    let pid = pm.doc.items[1].id
    pm.beginChange()
    pm.setPlacement(pid, page: 1, origin: CGPoint(x: s.margin, y: s.margin))
    pm.finishFreeEdit()
    check(pm.doc.item(pid)?.pageIndex == 1 && pm.doc.pageCount == 2, "拖到第 2 页")
    pm.beginChange()
    pm.setPlacement(pid, page: 0, origin: CGPoint(x: s.margin, y: s.margin + 100))
    pm.finishFreeEdit()
    check(pm.doc.item(pid)?.pageIndex == 0, "从第 2 页拖回第 1 页（实际页 \((pm.doc.item(pid)?.pageIndex ?? -1) + 1)）")
    check(pm.doc.item(pid)?.origin.y == s.margin + 100, "拖回后保持放置位置")
}

print(failures == 0 ? "\n全部通过 ✅" : "\n\(failures) 项失败 ❌")
exit(failures == 0 ? 0 : 1)