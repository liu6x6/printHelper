#if os(macOS)
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// macOS 主编辑器：Word 式连续页面 + 自由摆放（M1）
struct MacEditorView: View {
    @State private var model = EditorModel(layoutMode: .free)
    @State private var zoom: CGFloat = 1.0
    @State private var showCut = false
    /// 打印任务：runModal 是异步的，必须持有，否则 view/operation 提前释放 → 打不出东西
    @State private var activePrint: NSPrintOperation?
    @State private var busyText: String?
    @State private var errorMessage: String?
    @State private var statusText: String?

    /// 目录缓存（工程文件夹 / 导出目录 / 导入目录，跨启动保留访问权）
    private var workspace: WorkspaceStore { WorkspaceStore.shared }

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
            importDropped(urls)
        }
        .toolbar { toolbarContent }
        .navigationTitle("PrintHelper")
        .navigationSubtitle(subtitle)
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
        .focusedSceneValue(\.exportPDFAction, model.doc.items.isEmpty ? nil : { export(.pdf) })
        .focusedSceneValue(\.saveProjectAction, saveProject)
        .focusedSceneValue(\.openProjectAction, openProjectPanel)
        .overlay { statusOverlay }
        .alert("出错了", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onOpenURL { url in openProject(at: url) }   // Finder 双击 / 「打开方式」.phdoc
        .task { ExportService.cleanTempExports() }
    }

    private var subtitle: String {
        var text = "共 \(model.pages.count) 页 · A4"
        if let dir = workspace.workspaceName { text += " · 工程文件夹：\(dir)" }
        return text
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                openProjectPanel()
            } label: {
                Label("打开工程", systemImage: workspace.hasWorkspace ? "folder.fill" : "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            .help(workspace.hasWorkspace
                  ? "打开 .phdoc 工程文件（⌘O）· 已记住文件夹「\(workspace.workspaceName ?? "")」"
                  : "打开 .phdoc 工程文件（⌘O）")

            Button(action: saveProject) {
                Label("保存工程", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(model.doc.items.isEmpty)
            .help(workspace.hasWorkspace
                  ? "保存可编辑工程（⌘S）· 默认存到「\(workspace.workspaceName ?? "")」"
                  : "保存可编辑工程（⌘S），所在文件夹会被记住")

            Divider()

            Button {
                importImagesPanel()
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
            .help("打印全部页（⌘P）")

            Button {
                export(.pdf)
            } label: {
                Label("导出 PDF", systemImage: "square.and.arrow.down.on.square")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model.doc.items.isEmpty)
            .help("导出标准 A4 PDF（⌘E，也可用文件菜单）")

            Menu {
                Button("每页 PNG（300 DPI）") { export(.pagePNG) }
                Button("每页 JPG（300 DPI）") { export(.pageJPG) }
                Divider()
                Button("长图 PNG（拼接全部页）") { export(.longPNG) }
                Button("长图 JPG（拼接全部页）") { export(.longJPG) }
            } label: {
                Label("导出图片", systemImage: "photo.on.rectangle")
            }
            .disabled(model.doc.items.isEmpty)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("导出 PNG / JPG：每页一张，或全部页拼成长图")
        }
    }

    // MARK: - 打印（全部页）

    private func printDocument() {
        guard !model.doc.items.isEmpty else {
            errorMessage = ExportError.empty.localizedDescription
            return
        }
        let doc = model.doc
        busyText = "正在生成打印数据…"
        Task.detached(priority: .userInitiated) {
            let data = PDFRenderer.pdfData(for: doc)
            await MainActor.run {
                busyText = nil
                guard let data else {
                    errorMessage = "生成打印数据失败"
                    return
                }
                // PDFPrintView 实现了 knowsPageRange/rectForPage → 打印**全部页**
                guard let op = MacPrinter.makeOperation(for: data) else {
                    errorMessage = "没有可打印的内容"
                    return
                }
                activePrint = op          // 必须持有：runModal 是异步的
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                } else {
                    op.run()
                }
            }
        }
    }

    // MARK: - 导出（后台渲染 → NSSavePanel，记住上次目录）

    private func export(_ kind: ExportKind) {
        guard !model.doc.items.isEmpty else {
            errorMessage = ExportError.empty.localizedDescription
            return
        }
        let doc = model.doc
        busyText = "\(kind.label)…"
        Task.detached(priority: .userInitiated) {
            let result = Result { try ExportService.render(doc: doc, kind: kind) }
            await MainActor.run {
                busyText = nil
                switch result {
                case .success(let files): saveRendered(files, kind: kind)
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveRendered(_ files: [RenderedFile], kind: ExportKind) {
        guard let first = files.first else { return }
        workspace.withExportDir { cachedDir in
            if files.count == 1 {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [kind.contentType]
                panel.nameFieldStringValue = first.name
                panel.canCreateDirectories = true
                panel.directoryURL = cachedDir     // ← 上次导出的目录
                panel.prompt = "导出"
                panel.message = "\(kind.label)（目录已记住，下次直接定位到这里）"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try first.data.write(to: url, options: .atomic)
                    workspace.rememberExportDir(url)
                    status("已导出 \(url.lastPathComponent)")
                } catch {
                    errorMessage = "写入失败：\(error.localizedDescription)"
                }
            } else {
                // 每页一张：选目录后一次性写出全部文件
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                panel.directoryURL = cachedDir
                panel.prompt = "导出到这里"
                panel.message = "\(kind.label)：\(files.count) 个文件"
                guard panel.runModal() == .OK, let dir = panel.url else { return }
                workspace.rememberExportDir(dir)
                do {
                    for file in files {
                        try file.data.write(to: dir.appendingPathComponent(file.name), options: .atomic)
                    }
                    status("已导出 \(files.count) 个文件到 \(dir.lastPathComponent)")
                } catch {
                    errorMessage = "写入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 工程：打开 / 保存（记住文件夹）

    private func openProjectPanel() {
        workspace.withWorkspaceDir { cachedDir in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.phDocument]
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = true      // .phdoc 是目录包
            panel.treatsFilePackagesAsDirectories = false
            panel.directoryURL = cachedDir         // ← 上次打开/保存的文件夹
            panel.prompt = "打开"
            panel.message = "选择 .phdoc 工程（所在文件夹会被记住）"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            openProject(at: url)
        }
    }

    private func openProject(at url: URL) {
        do {
            let wrapper = try workspace.loadProject(at: url)
            try model.openProject(wrapper)
            status("已打开 \(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProject() {
        guard !model.doc.items.isEmpty else {
            errorMessage = ExportError.empty.localizedDescription
            return
        }
        do {
            let wrapper = try model.saveProject()
            workspace.withWorkspaceDir { cachedDir in
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.phDocument]
                panel.nameFieldStringValue = "\(workspace.suggestedProjectName()).\(ProjectFile.fileExtension)"
                panel.canCreateDirectories = true
                panel.directoryURL = cachedDir     // ← 上次的工程文件夹
                panel.prompt = "保存"
                panel.message = "保存可编辑工程 .phdoc（所在文件夹会被记住）"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    wrapper.preferredFilename = url.lastPathComponent
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)   // 目录包需要先删旧的
                    }
                    try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
                    workspace.rememberWorkspace(url)
                    status("已保存 \(url.lastPathComponent)")
                } catch {
                    errorMessage = "保存失败：\(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 导入

    private func importImagesPanel() {
        workspace.withImportDir { cachedDir in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.directoryURL = cachedDir         // ← 上次导入图片的文件夹
            panel.prompt = "导入"
            panel.message = "选择作业图片（可多选）"
            guard panel.runModal() == .OK else { return }
            let urls = panel.urls
            if let first = urls.first { workspace.rememberImportDir(first) }
            let datas = urls.compactMap { try? Data(contentsOf: $0) }
            guard !datas.isEmpty else {
                errorMessage = "没有可导入的图片"
                return
            }
            model.importImages(datas: datas)
        }
    }

    /// Finder 拖入：.phdoc 直接打开工程，其它当图片导入
    private func importDropped(_ urls: [URL]) -> Bool {
        if let project = urls.first(where: { $0.pathExtension == ProjectFile.fileExtension }) {
            openProject(at: project)
            return true
        }
        let datas = urls.compactMap { url -> Data? in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try? Data(contentsOf: url)
        }
        if let first = urls.first { workspace.rememberImportDir(first) }
        guard !datas.isEmpty else { return false }
        model.importImages(datas: datas)
        return true
    }

    // MARK: - 状态提示

    @ViewBuilder
    private var statusOverlay: some View {
        ZStack {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if let statusText {
                        Text(statusText)
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(radius: 3)
                            .padding(16)
                            .transition(.opacity)
                    }
                }
            }
            if let busyText {
                ProgressView(busyText)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: statusText)
    }

    private func status(_ text: String) {
        statusText = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if statusText == text { statusText = nil }
        }
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
    /// 移动/摆放光标：直接用 Media.xcassets 里的 **Arrowfourway** symbol（四向箭头），
    /// 白色描边垫底 + 深色主体，深浅背景都看得清；热点在图形中心。
    static let moveArrow: NSCursor = symbolCursor(named: "Arrowfourway", pointSize: 22) ?? .crosshair

    /// 把 asset catalog 里的 symbol 渲染成光标（2x 位图，Retina 不糊）
    private static func symbolCursor(named name: String, pointSize: CGFloat) -> NSCursor? {
        guard let configured = NSImage(named: name)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        else { return nil }
        let glyph = configured.size
        guard glyph.width > 1, glyph.height > 1 else { return nil }

        // 白色放大版垫底当描边，深色原尺寸叠在上面
        let pad: CGFloat = 2.5
        let size = NSSize(width: glyph.width + pad * 2, height: glyph.height + pad * 2)
        let white = tinted(configured, color: .white)
        let dark = tinted(configured, color: NSColor(white: 0.1, alpha: 1))

        guard let rep = bitmapRep(size: size) else { return nil }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        white.draw(in: NSRect(origin: .zero, size: size))
        dark.draw(in: NSRect(x: pad, y: pad, width: glyph.width, height: glyph.height))
        NSGraphicsContext.restoreGraphicsState()

        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }

    /// 单色化：用 destinationIn 把 symbol 的 alpha 轮廓填成指定颜色
    private static func tinted(_ src: NSImage, color: NSColor) -> NSImage {
        let size = src.size
        guard let rep = bitmapRep(size: size) else { return src }
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return src }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        src.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .destinationIn, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    private static func bitmapRep(size: NSSize, scale: CGFloat = 2) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int((size.width * scale).rounded())),
            pixelsHigh: max(1, Int((size.height * scale).rounded())),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        rep?.size = size
        return rep
    }

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
                    if hovering { Cursors.moveArrow.set() } else { NSCursor.arrow.set() }
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
                Cursors.moveArrow.set()
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