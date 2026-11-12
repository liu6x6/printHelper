#if os(iOS)
import SwiftUI
import PhotosUI
import UIKit

/// iOS 主界面：预览 / 排序调整 两种模式（M2）
struct IOSEditorView: View {
    @State private var model = EditorModel(layoutMode: .flow)
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mode = 0
    @State private var cutTarget: ImageItem?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var isImporting = false
    @State private var showProjectImporter = false
    @State private var showProjectExporter = false
    @State private var projectDoc = ProjectDocument(wrapper: FileWrapper(directoryWithFileWrappers: [:]))

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("", selection: $mode) {
                    Text("排版预览").tag(0)
                    Text("排序与调整").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if model.doc.items.isEmpty {
                    emptyState
                } else if mode == 0 {
                    preview
                } else {
                    itemList
                }
            }
            .navigationTitle("PrintHelper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                isImporting = true
                Task {
                    var datas: [Data] = []
                    for item in newItems {
                        if let d = try? await item.loadTransferable(type: Data.self) {
                            datas.append(d)
                        }
                    }
                    model.importImages(datas: datas)
                    pickerItems = []
                    isImporting = false
                }
            }
            .sheet(item: $cutTarget) { item in
                if let asset = model.doc.assets[item.assetID] {
                    CutSheetView(asset: asset) { f, dir in
                        model.cut(itemID: item.id, atFraction: f, direction: dir)
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityShareSheet(items: shareItems)
            }
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
            .overlay {
                if isImporting {
                    ProgressView("正在导入…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("从相册导入作业图片")
                .font(.headline)
            Text("图片将按 A4 宽度自动排列\n可排序、缩放、切割，导出 PDF 打印")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $pickerItems, matching: .images) {
                Label("选择图片", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 预览

    private var preview: some View {
        GeometryReader { geo in
            let scale = max(0.1, (geo.size.width - 32) / A4.width)
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(model.pages.enumerated()), id: \.offset) { idx, entries in
                        VStack(spacing: 4) {
                            PagePreviewView(doc: model.doc, entries: entries, scale: scale)
                                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                            Text("第 \(idx + 1) 页")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("共 \(model.pages.count) 页 · A4 · 导出即打印")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

    // MARK: - 排序与调整

    private var itemList: some View {
        List {
            ForEach(model.doc.items) { item in
                row(for: item)
            }
            .onMove { model.reorder(from: $0, to: $1) }
            .onDelete { model.delete(at: $0) }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    @ViewBuilder
    private func row(for item: ImageItem) -> some View {
        HStack(spacing: 12) {
            if let asset = model.doc.assets[item.assetID], let cg = asset.thumbnail {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Slider(
                    value: fractionBinding(item),
                    in: 0.1...1.0,
                    onEditingChanged: { began in
                        if began { model.beginChange() }
                    }
                )
                Text("宽度 \(Int((item.widthFraction * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button {
                cutTarget = item
            } label: {
                Image(systemName: "scissors")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                model.delete(itemID: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func fractionBinding(_ item: ImageItem) -> Binding<CGFloat> {
        Binding(
            get: { model.doc.item(item.id)?.widthFraction ?? item.widthFraction },
            set: { model.setFraction(item.id, $0) }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)

            PhotosPicker(selection: $pickerItems, matching: .images) {
                Image(systemName: "photo.badge.plus")
            }

            Menu {
                Button {
                    sharePDF()
                } label: {
                    Label("导出 PDF", systemImage: "doc.richtext")
                }
                Button {
                    shareImages()
                } label: {
                    Label("导出每页图片", systemImage: "photo")
                }
                Divider()
                Button {
                    saveProject()
                } label: {
                    Label("保存工程", systemImage: "tray.and.arrow.down")
                }
                Button {
                    showProjectImporter = true
                } label: {
                    Label("打开工程", systemImage: "folder")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(model.doc.items.isEmpty)
        }
    }

    // MARK: - 工程保存

    private func saveProject() {
        guard let wrapper = try? model.saveProject() else { return }
        projectDoc = ProjectDocument(wrapper: wrapper)
        showProjectExporter = true
    }

    // MARK: - 导出分享

    private func sharePDF() {
        guard let data = model.exportPDF() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("作业.pdf")
        do {
            try data.write(to: url, options: .atomic)
            shareItems = [url]
            showShare = true
        } catch {}
    }

    private func shareImages() {
        let datas = model.exportPagePNGs()
        let urls: [URL] = datas.enumerated().compactMap { i, d in
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("作业-第\(i + 1)页.png")
            do {
                try d.write(to: u, options: .atomic)
                return u
            } catch { return nil }
        }
        guard !urls.isEmpty else { return }
        shareItems = urls
        showShare = true
    }
}

/// 系统分享面板
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif