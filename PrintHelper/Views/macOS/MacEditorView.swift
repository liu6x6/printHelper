#if os(macOS)
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// macOS 主编辑器：Word 式连续页面 + 自由摆放（M1）
struct MacEditorView: View {
    @State private var model = EditorModel(layoutMode: .free)
    @State private var zoom: CGFloat = 1.0
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showCut = false
    @State private var exportDoc = PDFExportDocument(data: Data())
    @State private var showProjectImporter = false
    @State private var showProjectExporter = false
    @State private var projectDoc = ProjectDocument(wrapper: FileWrapper(directoryWithFileWrappers: [:]))

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            MacDocumentCanvas(
                model: model,
                zoom: zoom,
                onCutRequest: { id in
                    model.selectedID = id
                    showCut = true
                }
            )
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            let datas = urls.compactMap { try? Data(contentsOf: $0) }
            model.importImages(datas: datas)
            return !datas.isEmpty
        }
        .toolbar { toolbarContent }
        .navigationTitle("PrintHelper")
        .navigationSubtitle("共 \(model.pages.count) 页 · A4")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let datas = urls.compactMap { url -> Data? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try? Data(contentsOf: url)
                }
                model.importImages(datas: datas)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .pdf,
            defaultFilename: "作业"
        ) { _ in }
        .fileImporter(
            isPresented: $showProjectImporter,
            allowedContentTypes: [.phDocument],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let wrapper = try? FileWrapper(url: url, options: .immediate) {
                    try? model.openProject(wrapper)
                }
            }
        }
        .fileExporter(
            isPresented: $showProjectExporter,
            document: projectDoc,
            contentType: .phDocument,
            defaultFilename: "作业"
        ) { _ in }
        .sheet(isPresented: $showCut) {
            if let item = model.selectedItem, let asset = model.doc.asset(for: item) {
                CutSheetView(asset: asset) { result in
                    switch result {
                    case .single(let f, let dir):
                        model.cut(itemID: item.id, atFraction: f, direction: dir)
                    case .equal(let n, let dir):
                        model.splitEqual(itemID: item.id, parts: n, direction: dir)
                    }
                }
            }
        }
        .onDeleteCommand { model.deleteSelected() }
        .focusedSceneValue(\.exportPDFAction, model.doc.items.isEmpty ? nil : exportPDF)
        .focusedSceneValue(\.saveProjectAction, saveProject)
        .focusedSceneValue(\.openProjectAction, { showProjectImporter = true })
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showProjectImporter = true
            } label: {
                Label("打开工程", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            .help("打开 .phdoc 工程文件（⌘O）")

            Button(action: saveProject) {
                Label("保存工程", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("保存可编辑工程（⌘S）")

            Divider()

            Button {
                showImporter = true
            } label: {
                Label("导入图片", systemImage: "photo.badge.plus")
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("导入图片（⇧⌘I），也可直接拖入文件")

            Button(action: pasteFromClipboard) {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: .command)
            .help("粘贴剪贴板图片（⌘V）")

            Divider()

            Button {
                if model.selectedItem != nil { showCut = true }
            } label: {
                Label("切割", systemImage: "scissors")
            }
            .disabled(model.selectedItem == nil)
            .help("切割选中图片：自由/N 等分，横向/纵向（也可双击图片）")

            Button {
                if let id = model.selectedID { model.rotate(itemID: id) }
            } label: {
                Label("旋转", systemImage: "rotate.right")
            }
            .disabled(model.selectedItem == nil)
            .help("顺时针旋转 90°")

            Button {
                model.deleteSelected()
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(model.selectedItem == nil)
            .keyboardShortcut(.delete, modifiers: [])
            .help("删除选中图片（Delete 键）")

            Divider()

            Button {
                model.undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .keyboardShortcut("z", modifiers: .command)

            Button {
                model.redo()
            } label: {
                Label("重做", systemImage: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()

            Button {
                zoom = max(0.4, zoom - 0.1)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int((zoom * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44)
            Button {
                zoom = min(2.0, zoom + 0.1)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }

            if let sel = model.selectedItem {
                Divider()
                TextField("宽度%", value: percentBinding(sel.id), format: .number)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .help("精确设置选中图片宽度比例（回车生效）")
                Text("%")
            }

            Divider()

            Button(action: printDocument) {
                Label("打印", systemImage: "printer")
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(model.doc.items.isEmpty)
            .help("直接打印（⌘P）")

            Button(action: exportPDF) {
                Label("导出 PDF", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model.doc.items.isEmpty)
            .help("导出标准 A4 PDF（⌘E，也可用文件菜单）")
        }
    }

    private func printDocument() {
        guard let data = model.exportPDF(), let document = PDFDocument(data: data) else { return }
        let pdfView = PDFView(frame: NSRect(x: 0, y: 0, width: A4.width, height: A4.height))
        pdfView.document = document
        pdfView.autoScales = true
        let op = NSPrintOperation(view: pdfView, printInfo: .shared)
        op.run()
    }

    private func exportPDF() {
        guard let data = model.exportPDF() else { return }
        exportDoc = PDFExportDocument(data: data)
        showExporter = true
    }

    private func saveProject() {
        guard let wrapper = try? model.saveProject() else { return }
        projectDoc = ProjectDocument(wrapper: wrapper)
        showProjectExporter = true
    }

    private func percentBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { Double((model.doc.item(id)?.widthFraction ?? 1) * 100) },
            set: { newValue in
                model.beginChange()
                model.setFraction(id, CGFloat(newValue / 100))
                model.finishFreeEdit()
            }
        )
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        var datas: [Data] = []
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            datas.append(contentsOf: urls.compactMap { try? Data(contentsOf: $0) })
        }
        if datas.isEmpty {
            if let d = pb.data(forType: .png) {
                datas.append(d)
            } else if let d = pb.data(forType: .tiff) {
                datas.append(d)
            }
        }
        model.importImages(datas: datas)
    }
}

/// 对齐吸附参考线（E-5）
struct SnapGuide: Identifiable {
    let id = UUID()
    let isVertical: Bool
    let position: CGFloat  // 画布视图坐标
}

/// 整篇统一画布：所有页面 + 所有图片在同一坐标系，
/// 拖拽可实时跨页（修复：无法从第 2 页拖回第 1 页）
struct MacDocumentCanvas: View {
    let model: EditorModel
    let zoom: CGFloat
    let onCutRequest: (UUID) -> Void

    @State private var guides: [SnapGuide] = []

    /// 页间距（含页码标签区域）
    static let pageGap: CGFloat = 44
    var stride: CGFloat { A4.height * zoom + Self.pageGap }

    var body: some View {
        let pageCount = model.pages.count
        ZStack(alignment: .topLeading) {
            ForEach(0..<pageCount, id: \.self) { idx in
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(.white)
                        .frame(width: A4.width * zoom, height: A4.height * zoom)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedID = nil }
                    Text("第 \(idx + 1) 页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .offset(y: CGFloat(idx) * stride)
            }
            ForEach(model.doc.items) { item in
                let size = model.doc.size(of: item)
                let gf = CGRect(
                    x: item.origin.x * zoom,
                    y: CGFloat(item.pageIndex) * stride + item.origin.y * zoom,
                    width: size.width * zoom,
                    height: size.height * zoom
                )
                MacItemView(
                    model: model,
                    item: item,
                    globalFrame: gf,
                    zoom: zoom,
                    stride: stride,
                    onCutRequest: onCutRequest,
                    onGuides: { guides = $0 }
                )
            }
            ForEach(guides) { g in
                Rectangle()
                    .fill(Color.pink.opacity(0.9))
                    .frame(width: g.isVertical ? 1 : A4.width * zoom,
                           height: g.isVertical ? CGFloat(pageCount) * stride : 1)
                    .offset(x: g.isVertical ? g.position : 0, y: g.isVertical ? 0 : g.position)
                    .allowsHitTesting(false)
            }
        }
        .frame(
            width: A4.width * zoom,
            height: CGFloat(pageCount - 1) * stride + A4.height * zoom + 24,
            alignment: .topLeading
        )
    }
}

/// 光标工具
enum Cursors {
    /// 对角双向箭头（角点缩放）
    static let diagonalResize: NSCursor = {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)?
            .draw(in: NSRect(origin: .zero, size: size))
        img.unlockFocus()
        return NSCursor(image: img, hotSpot: NSPoint(x: 9, y: 9))
    }()
}

/// 可拖动 / 可缩放的图片对象（全局坐标，拖拽时实时跨页）
struct MacItemView: View {
    let model: EditorModel
    let item: ImageItem
    let globalFrame: CGRect
    let zoom: CGFloat
    let stride: CGFloat
    let onCutRequest: (UUID) -> Void
    let onGuides: ([SnapGuide]) -> Void

    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGFloat?
    @State private var isDragging = false
    @State private var isResizing = false

    private var isSelected: Bool { model.selectedID == item.id }
    private var usableW: CGFloat { model.doc.settings.usableWidth }
    private var aspect: CGFloat { model.doc.assets[item.assetID]?.aspectRatio ?? 1 }

    var body: some View {
        let w = globalFrame.width
        let h = globalFrame.height
        ZStack {
            imageView(w: w, h: h)
            if isSelected {
                handles(w: w, h: h)
            }
        }
        .offset(x: globalFrame.minX, y: globalFrame.minY)
    }

    @ViewBuilder
    private func imageView(w: CGFloat, h: CGFloat) -> some View {
        if let asset = model.doc.assets[item.assetID], let cg = asset.thumbnail {
            Image(decorative: cg, scale: 1)
                .resizable()
                .frame(width: w, height: h)
                .overlay {
                    if isSelected {
                        Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard !isDragging, !isResizing else { return }
                    if hovering { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
                }
                .onTapGesture(count: 2) { onCutRequest(item.id) }
                .onTapGesture { model.selectedID = item.id }
                .gesture(moveGesture)
        } else {
            Rectangle().fill(.gray.opacity(0.2)).frame(width: w, height: h)
        }
    }

    private var moveGesture: some Gesture {
        // 关键修复：用 .global 坐标系。默认 .local 会随图片移动，
        // translation 被“吃掉”一部分，导致图片不跟手（跨页时尤其明显）
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = globalFrame.origin
                    model.beginChange()
                    model.selectedID = item.id
                    isDragging = true
                }
                NSCursor.crosshair.set()
                let start = dragStart ?? globalFrame.origin
                let gx = start.x + v.translation.width
                let gy = start.y + v.translation.height
                // 根据全局 y 实时判定所在页；允许拖出最后一页（松手时自动扩页）
                let page = min(max(Int(gy / stride), 0), model.doc.pageCount)
                let localY = gy - CGFloat(page) * stride
                var origin = CGPoint(x: gx / zoom, y: localY / zoom)

                // 对齐吸附（E-5）：页边距/中线 + 同页其他图片边缘
                let size = model.doc.size(of: item)
                let s = model.doc.settings
                let threshold = 6 / zoom
                let others = model.doc.items
                    .filter { $0.pageIndex == page && $0.id != item.id }
                    .map { model.doc.frame(of: $0) }
                var newGuides: [SnapGuide] = []

                var xTargets: [CGFloat] = [s.margin, A4.width / 2, s.margin + s.usableWidth]
                xTargets += others.flatMap { [$0.minX, $0.midX, $0.maxX] }
                let xEdges = [origin.x, origin.x + size.width / 2, origin.x + size.width]
                var bestDX: CGFloat?
                var bestX: CGFloat = 0
                for t in xTargets {
                    for e in xEdges {
                        let d = t - e
                        if abs(d) < threshold, bestDX == nil || abs(d) < abs(bestDX!) {
                            bestDX = d
                            bestX = t
                        }
                    }
                }
                if let d = bestDX {
                    origin.x += d
                    newGuides.append(SnapGuide(isVertical: true, position: bestX * zoom))
                }

                var yTargets: [CGFloat] = [s.margin, s.margin + s.usableHeight]
                yTargets += others.flatMap { [$0.minY, $0.maxY] }
                let yEdges = [origin.y, origin.y + size.height]
                var bestDY: CGFloat?
                var bestY: CGFloat = 0
                for t in yTargets {
                    for e in yEdges {
                        let d = t - e
                        if abs(d) < threshold, bestDY == nil || abs(d) < abs(bestDY!) {
                            bestDY = d
                            bestY = t
                        }
                    }
                }
                if let d = bestDY {
                    origin.y += d
                    newGuides.append(SnapGuide(isVertical: false, position: CGFloat(page) * stride + bestY * zoom))
                }

                model.setPlacement(item.id, page: page, origin: origin)
                onGuides(newGuides)
            }
            .onEnded { _ in
                dragStart = nil
                isDragging = false
                NSCursor.arrow.set()
                onGuides([])
                model.finishFreeEdit()
            }
    }

    // MARK: - 缩放手柄（四边中点 + 角点，各配对应光标）

    @ViewBuilder
    private func handles(w: CGFloat, h: CGFloat) -> some View {
        resizeHandle(size: CGSize(width: 6, height: 20), offset: CGSize(width: -w / 2, height: 0),
                     cursor: .resizeLeftRight) { -$0.width / zoom / usableW }
        resizeHandle(size: CGSize(width: 6, height: 20), offset: CGSize(width: w / 2, height: 0),
                     cursor: .resizeLeftRight) { $0.width / zoom / usableW }
        resizeHandle(size: CGSize(width: 20, height: 6), offset: CGSize(width: 0, height: -h / 2),
                     cursor: .resizeUpDown) { -$0.height / zoom / (usableW * aspect) }
        resizeHandle(size: CGSize(width: 20, height: 6), offset: CGSize(width: 0, height: h / 2),
                     cursor: .resizeUpDown) { $0.height / zoom / (usableW * aspect) }
        resizeHandle(size: CGSize(width: 14, height: 14), offset: CGSize(width: w / 2, height: h / 2),
                     cursor: Cursors.diagonalResize, isCircle: true) { $0.width / zoom / usableW }
    }

    private func resizeHandle(
        size: CGSize,
        offset: CGSize,
        cursor: NSCursor,
        isCircle: Bool = false,
        delta: @escaping (CGSize) -> CGFloat
    ) -> some View {
        Group {
            if isCircle {
                Circle().fill(Color.accentColor)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            } else {
                Capsule().fill(Color.accentColor)
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: offset.width, y: offset.height)
        .onHover { hovering in
            guard !isDragging, !isResizing else { return }
            if hovering { cursor.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if resizeStart == nil {
                        resizeStart = item.widthFraction
                        model.beginChange()
                        isResizing = true
                    }
                    cursor.set()
                    model.setFraction(item.id, (resizeStart ?? item.widthFraction) + delta(v.translation))
                }
                .onEnded { _ in
                    resizeStart = nil
                    isResizing = false
                    NSCursor.arrow.set()
                    model.finishFreeEdit()
                }
        )
    }
}
#endif