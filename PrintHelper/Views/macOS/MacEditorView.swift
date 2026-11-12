#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// macOS 主编辑器：Word 式连续页面 + 自由摆放（M1）
struct MacEditorView: View {
    @State private var model = EditorModel(layoutMode: .free)
    @State private var zoom: CGFloat = 1.0
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var showCut = false
    @State private var exportDoc = PDFExportDocument(data: Data())

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
        .sheet(isPresented: $showCut) {
            if let item = model.selectedItem, let asset = model.doc.asset(for: item) {
                CutSheetView(asset: asset) { f in
                    model.cut(itemID: item.id, atFraction: f)
                }
            }
        }
        .onDeleteCommand { model.deleteSelected() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showImporter = true
            } label: {
                Label("导入图片", systemImage: "photo.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
            .help("导入图片（⌘O），也可直接拖入文件")

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
            .help("横向切割选中图片（也可双击图片）")

            Button {
                model.deleteSelected()
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(model.selectedItem == nil)

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

            Divider()

            Button(action: exportPDF) {
                Label("导出 PDF", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model.doc.items.isEmpty)
        }
    }

    private func exportPDF() {
        guard let data = model.exportPDF() else { return }
        exportDoc = PDFExportDocument(data: data)
        showExporter = true
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

/// 整篇统一画布：所有页面 + 所有图片在同一坐标系，
/// 拖拽可实时跨页（修复：无法从第 2 页拖回第 1 页）
struct MacDocumentCanvas: View {
    let model: EditorModel
    let zoom: CGFloat
    let onCutRequest: (UUID) -> Void

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
                    onCutRequest: onCutRequest
                )
            }
        }
        .frame(
            width: A4.width * zoom,
            height: CGFloat(pageCount - 1) * stride + A4.height * zoom + 24,
            alignment: .topLeading
        )
    }
}

/// 可拖动 / 可缩放的图片对象（全局坐标，拖拽时实时跨页）
struct MacItemView: View {
    let model: EditorModel
    let item: ImageItem
    let globalFrame: CGRect
    let zoom: CGFloat
    let stride: CGFloat
    let onCutRequest: (UUID) -> Void

    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGFloat?

    private var isSelected: Bool { model.selectedID == item.id }

    var body: some View {
        let w = globalFrame.width
        let h = globalFrame.height
        ZStack(alignment: .bottomTrailing) {
            imageView(w: w, h: h)
            if isSelected {
                resizeHandle
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
                .onTapGesture(count: 2) { onCutRequest(item.id) }
                .onTapGesture { model.selectedID = item.id }
                .gesture(moveGesture)
        } else {
            Rectangle().fill(.gray.opacity(0.2)).frame(width: w, height: h)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = globalFrame.origin
                    model.beginChange()
                    model.selectedID = item.id
                }
                let start = dragStart ?? globalFrame.origin
                let gx = start.x + v.translation.width
                let gy = start.y + v.translation.height
                // 根据全局 y 实时判定所在页；允许拖出最后一页（松手时自动扩页）
                let page = min(max(Int(gy / stride), 0), model.doc.pageCount)
                let localY = gy - CGFloat(page) * stride
                model.setPlacement(item.id, page: page, origin: CGPoint(x: gx / zoom, y: localY / zoom))
            }
            .onEnded { _ in
                dragStart = nil
                model.finishFreeEdit()
            }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .offset(x: 7, y: 7)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        if resizeStart == nil {
                            resizeStart = item.widthFraction
                            model.beginChange()
                        }
                        let start = resizeStart ?? item.widthFraction
                        let f = start + v.translation.width / zoom / model.doc.settings.usableWidth
                        model.setFraction(item.id, f)
                    }
                    .onEnded { _ in
                        resizeStart = nil
                        model.finishFreeEdit()
                    }
            )
    }
}
#endif