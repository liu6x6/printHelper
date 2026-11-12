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
            VStack(spacing: 20) {
                ForEach(Array(model.pages.enumerated()), id: \.offset) { idx, entries in
                    VStack(spacing: 6) {
                        MacPageCanvas(
                            model: model,
                            pageIndex: idx,
                            entries: entries,
                            zoom: zoom,
                            onCutRequest: { id in
                                model.selectedID = id
                                showCut = true
                            }
                        )
                        Text("第 \(idx + 1) 页")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(minWidth: A4.width * zoom + 56)
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

/// 单页画布：白纸 + 可交互图片
struct MacPageCanvas: View {
    let model: EditorModel
    let pageIndex: Int
    let entries: [LayoutEngine.Entry]
    let zoom: CGFloat
    let onCutRequest: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
            ForEach(entries, id: \.item.id) { entry in
                MacItemView(
                    model: model,
                    item: entry.item,
                    frame: entry.frame,
                    zoom: zoom,
                    onCutRequest: onCutRequest
                )
            }
        }
        .frame(width: A4.width * zoom, height: A4.height * zoom)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = nil }
    }
}

/// 可拖动 / 可缩放的图片对象
struct MacItemView: View {
    let model: EditorModel
    let item: ImageItem
    let frame: CGRect
    let zoom: CGFloat
    let onCutRequest: (UUID) -> Void

    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGFloat?

    private var isSelected: Bool { model.selectedID == item.id }

    var body: some View {
        let w = frame.width * zoom
        let h = frame.height * zoom
        ZStack(alignment: .bottomTrailing) {
            imageView(w: w, h: h)
            if isSelected {
                resizeHandle
            }
        }
        .offset(x: frame.minX * zoom, y: frame.minY * zoom)
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
                    dragStart = item.origin
                    model.beginChange()
                    model.selectedID = item.id
                }
                let start = dragStart ?? item.origin
                model.setOrigin(item.id, to: CGPoint(
                    x: start.x + v.translation.width / zoom,
                    y: start.y + v.translation.height / zoom
                ))
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