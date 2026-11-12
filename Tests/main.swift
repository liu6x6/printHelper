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

/// 上半红 / 下半蓝的测试图（用于验证导出方向）
func makeBicolorImage(w: Int, h: Int) -> Data {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: h / 2, width: w, height: h - h / 2))  // 上半（CG y 向上）
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))           // 下半
    return ImageCutter.pngData(ctx.makeImage()!)!
}

/// 解码为自上而下的 RGBA 像素 buffer
func topDownPixels(_ img: CGImage) -> [UInt8]? {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}
func isRed(_ buf: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    return i + 2 < buf.count && buf[i] > 180 && buf[i + 1] < 80 && buf[i + 2] < 80
}
func isBlue(_ buf: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    return i + 2 < buf.count && buf[i + 2] > 180 && buf[i] < 80 && buf[i + 1] < 80
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

    // ---- 10. 纵向切割（C-7）----
    let va = ImageAsset(data: makeImage(w: 800, h: 600, r: 0.5, g: 0.5, b: 0))
    let vparts = ImageCutter.cutVertical(asset: va, atXFraction: 0.25)!
    check(vparts.left.pixelSize == CGSize(width: 200, height: 600), "纵切左段 200x600（实际 \(vparts.left.pixelSize)）")
    check(vparts.right.pixelSize == CGSize(width: 600, height: 600), "纵切右段 600x600（实际 \(vparts.right.pixelSize)）")

    let vm = EditorModel(layoutMode: .free)
    vm.importImages(datas: [makeImage(w: 800, h: 600, r: 0.5, g: 0.5, b: 0)])
    let vid = vm.doc.items[0].id
    let origX = vm.doc.items[0].origin.x
    vm.cut(itemID: vid, atFraction: 0.25, direction: .vertical)
    check(vm.doc.items.count == 2, "纵切后 2 段")
    let left = vm.doc.item(vid)!
    let right = vm.doc.items[1]
    check(abs(left.widthFraction - 0.25) < 0.001 && abs(right.widthFraction - 0.75) < 0.001, "纵切保持视觉比例：25% / 75%")
    check(right.origin.x > origX && right.origin.y == left.origin.y, "纵切右段摆在左段右侧同一行")
    vm.undo()
    check(vm.doc.items.count == 1, "撤销纵切")

    // ---- 11. 回归：导出方向（bug：PDF 内容上下颠倒）----
    let om = EditorModel(layoutMode: .flow)
    om.importImages(datas: [makeBicolorImage(w: 200, h: 200)])
    let ps = PageSettings()
    let imgH = ps.usableWidth  // 正方形图，铺满页宽
    // PNG（300 DPI）
    if let png = om.exportPagePNGs().first,
       let src = CGImageSourceCreateWithData(png as CFData, nil),
       let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
       let buf = topDownPixels(cg) {
        let sc = 300.0 / 72.0
        let cx = Int((ps.margin + imgH / 2) * sc)
        let yTop = Int((ps.margin + 40) * sc)
        let yBot = Int((ps.margin + imgH - 40) * sc)
        check(isRed(buf, cg.width, cx, yTop), "PNG：图片上部为红（正立）")
        check(isBlue(buf, cg.width, cx, yBot), "PNG：图片下部为蓝（正立）")
    } else {
        check(false, "PNG 方向测试导出失败")
    }
    // PDF（光栅化后采样）
    if let pdf = om.exportPDF(), let pdoc = PDFDocument(data: pdf), let page = pdoc.page(at: 0) {
        let sc: CGFloat = 2
        let w = Int(A4.width * sc), h = Int(A4.height * sc)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        if let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: sc, y: sc)
            page.draw(with: .mediaBox, to: ctx)
            let cx = Int((ps.margin + imgH / 2) * sc)
            let yTop = Int((ps.margin + 40) * sc)
            let yBot = Int((ps.margin + imgH - 40) * sc)
            check(isRed(buf, w, cx, yTop), "PDF：图片上部为红（正立）")
            check(isBlue(buf, w, cx, yBot), "PDF：图片下部为蓝（正立）")
        } else {
            check(false, "PDF 光栅化失败")
        }
    } else {
        check(false, "PDF 方向测试导出失败")
    }

    // ---- 12. 工程保存/打开往返（S-1）----
    let sm = EditorModel(layoutMode: .free)
    sm.importImages(datas: [
        makeImage(w: 600, h: 400, r: 1, g: 0, b: 0),
        makeImage(w: 400, h: 800, r: 0, g: 1, b: 0),
    ])
    let sid = sm.doc.items[0].id
    sm.cut(itemID: sid, atFraction: 0.3)
    sm.setFraction(sm.doc.items[1].id, 0.6)
    do {
        let wrapper = try sm.saveProject()
        let loaded = try EditorModel(layoutMode: .free)
        try loaded.openProject(wrapper)
        check(loaded.doc.items.count == sm.doc.items.count, "工程往返：图片数量一致")
        check(loaded.doc.pageCount == sm.doc.pageCount, "工程往返：页数一致")
        let sameFrames = zip(loaded.doc.items, sm.doc.items).allSatisfy { a, b in
            a.widthFraction == b.widthFraction && a.pageIndex == b.pageIndex && a.origin == b.origin
        }
        check(sameFrames, "工程往返：位置/缩放/页码一致")
        let samePixels = zip(loaded.doc.items, sm.doc.items).allSatisfy { a, b in
            loaded.doc.assets[a.assetID]?.pixelSize == sm.doc.assets[b.assetID]?.pixelSize
        }
        check(samePixels, "工程往返：图片像素一致（含切割结果）")
        loaded.undo()
        check(loaded.doc.items.isEmpty, "打开工程可撤销")
    } catch {
        check(false, "工程保存/打开抛错：\(error)")
    }

    // ---- 13. 旋转（E-10）----
    let ra = ImageAsset(data: makeImage(w: 800, h: 600, r: 0.3, g: 0.6, b: 0.9))
    let r90 = ImageCutter.rotated(asset: ra, quarterTurns: 1)!
    check(r90.pixelSize == CGSize(width: 600, height: 800), "旋转 90°：800x600 → 600x800")
    let r360 = ImageCutter.rotated(asset: r90, quarterTurns: 3)!
    check(r360.pixelSize == CGSize(width: 800, height: 600), "再转 270° 恢复原尺寸")
    // 方向：上红下蓝 顺时针 90° → 红在右
    let rb = ImageAsset(data: makeBicolorImage(w: 200, h: 200))
    let rb90 = ImageCutter.rotated(asset: rb, quarterTurns: 1)!
    if let cg = rb90.cgImage, let buf = topDownPixels(cg) {
        check(isRed(buf, cg.width, 150, 100), "旋转后红色在右（顺时针）")
        check(isBlue(buf, cg.width, 50, 100), "旋转后蓝色在左")
    } else {
        check(false, "旋转方向测试解码失败")
    }
    let rm2 = EditorModel(layoutMode: .flow)
    rm2.importImages(datas: [makeImage(w: 800, h: 600, r: 0.3, g: 0.6, b: 0.9)])
    let rid = rm2.doc.items[0].id
    rm2.rotate(itemID: rid)
    check(rm2.doc.assets[rm2.doc.items[0].assetID]?.pixelSize == CGSize(width: 600, height: 800), "模型旋转生效")
    rm2.undo()
    check(rm2.doc.assets[rm2.doc.items[0].assetID]?.pixelSize == CGSize(width: 800, height: 600), "撤销旋转")

    // ---- 14. N 等分切割（C-7）----
    let ea = ImageAsset(data: makeImage(w: 800, h: 600, r: 0.8, g: 0.4, b: 0.2))
    let eh = ImageCutter.split(asset: ea, heightFractions: [1.0/3, 1.0/3, 1.0/3])!
    check(eh.count == 3 && eh.allSatisfy { $0.pixelSize == CGSize(width: 800, height: 200) }, "横 3 等分：800x200 ×3")
    let ev = ImageCutter.splitVertical(asset: ea, widthFractions: [0.25, 0.25, 0.25, 0.25])!
    check(ev.count == 4 && ev.allSatisfy { $0.pixelSize == CGSize(width: 200, height: 600) }, "纵 4 等分：200x600 ×4")
    let em = EditorModel(layoutMode: .free)
    em.importImages(datas: [makeImage(w: 800, h: 600, r: 0.8, g: 0.4, b: 0.2)])
    em.splitEqual(itemID: em.doc.items[0].id, parts: 3, direction: .horizontal)
    check(em.doc.items.count == 3, "模型横 3 等分 → 3 段")
    em.undo()
    check(em.doc.items.count == 1, "撤销等分")
    em.splitEqual(itemID: em.doc.items[0].id, parts: 4, direction: .vertical)
    check(em.doc.items.count == 4, "模型纵 4 等分 → 4 段")
    check(em.doc.items.allSatisfy { abs($0.widthFraction - 0.25) < 0.001 }, "纵等分保持视觉比例 25%")

    // ---- 15. 长图导出（X-3）----
    let lm = EditorModel(layoutMode: .flow)
    lm.importImages(datas: [
        makeBicolorImage(w: 200, h: 200),
        makeImage(w: 200, h: 200, r: 0, g: 1, b: 0),
        makeImage(w: 200, h: 200, r: 0, g: 1, b: 0),
        makeImage(w: 200, h: 200, r: 0, g: 1, b: 0),
    ])
    let pageCount = lm.pages.count
    check(pageCount >= 2, "长图测试文档 ≥ 2 页（实际 \(pageCount)）")
    if let long = lm.exportLongImagePNG(),
       let src = CGImageSourceCreateWithData(long as CFData, nil),
       let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        let sc = 150.0 / 72.0
        let expectW = Int(A4.width * sc)
        let expectH = Int(A4.height * sc) * pageCount
        check(cg.width == expectW && cg.height == expectH, "长图尺寸 = \(pageCount) 页拼接（实际 \(cg.width)x\(cg.height)）")
        if let buf = topDownPixels(cg) {
            let ps2 = PageSettings()
            let cx = Int((ps2.margin + ps2.usableWidth / 2) * sc)
            let yTop = Int((ps2.margin + 40) * sc)
            check(isRed(buf, cg.width, cx, yTop), "长图第一页方向正立")
        }
    } else {
        check(false, "长图导出失败")
    }
}

print(failures == 0 ? "\n全部通过 ✅" : "\n\(failures) 项失败 ❌")
exit(failures == 0 ? 0 : 1)