#if os(iOS)
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// iOS 主界面：预览 / 排序调整 两种模式（M2）
struct IOSEditorView: View {
    @State private var model = EditorModel(layoutMode: .flow)
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mode = 0
    @State private var cutTarget: ImageItem?
    @State private var scaleTarget: ImageItem?
    @State private var scaleText = ""
    @Environment(\.horizontalSizeClass) private var hSize

    // 分享 / 导出
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var busyText: String?
    @State private var errorMessage: String?
    @State private var toastText: String?

    // 工程打开 / 保存（含目录缓存）
    @State private var showProjectImporter = false      // 系统面板：选 .phdoc
    @State private var showProjectExporter = false      // 另存到「文件」
    @State private var showProjectList = false          // 工作文件夹里的工程列表
    @State private var showSaveNameAlert = false
    @State private var saveName = "作业"
    @State private var pendingWrapper: FileWrapper?
    @State private var projectDoc = ProjectDocument(wrapper: FileWrapper(directoryWithFileWrappers: [:]))
    @State private var pickIntent: PickIntent = .openProjectFile

    /// 目录缓存（安全作用域书签，跨启动保留访问权）
    private var workspace: WorkspaceStore { WorkspaceStore.shared }

    /// 文件面板意图：决定 allowedContentTypes 与选完之后的动作
    private enum PickIntent: Equatable {
        case openProjectFile   // 选一个 .phdoc 打开
        case pickFolderToSave  // 选工作文件夹，然后保存工程
        case pickFolderToOpen  // 选工作文件夹，然后列出里面的工程
        case pickFolderOnly    // 只更换工作文件夹

        var isFolder: Bool { self != .openProjectFile }
    }

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
            .navigationTitle(hSize == .regular ? "PrintHelper" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: pickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                busyText = "正在导入…"
                Task {
                    var datas: [Data] = []
                    for item in newItems {
                        if let d = try? await item.loadTransferable(type: Data.self) {
                            datas.append(d)
                        }
                    }
                    model.importImages(datas: datas)
                    pickerItems = []
                    busyText = nil
                }
            }
            .sheet(item: $cutTarget) { item in
                if let asset = model.doc.assets[item.assetID] {
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
            .sheet(isPresented: $showShare) {
                ActivityShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showProjectList) {
                projectListSheet
            }
            // 系统文件面板：按意图切换「选 .phdoc」或「选文件夹」
            .fileImporter(
                isPresented: $showProjectImporter,
                allowedContentTypes: pickIntent.isFolder ? [.folder] : [.phDocument],
                allowsMultipleSelection: false
            ) { result in
                handlePick(result)
            }
            .fileExporter(
                isPresented: $showProjectExporter,
                document: projectDoc,
                contentType: .phDocument,
                defaultFilename: saveName.isEmpty ? "作业" : saveName
            ) { result in
                if case .success(let url) = result {
                    workspace.rememberExportDir(url)
                    toast("已保存到「文件」：\(url.lastPathComponent)")
                }
            }
            .alert("保存工程", isPresented: $showSaveNameAlert) {
                TextField("工程名", text: $saveName)
                Button("保存") {
                    if let wrapper = pendingWrapper {
                        performSave(wrapper, name: saveName)
                    }
                    pendingWrapper = nil
                }
                Button("取消", role: .cancel) { pendingWrapper = nil }
            } message: {
                Text("保存到已缓存的文件夹「\(workspace.workspaceName ?? "未选择")」\n下次点保存会直接写回这里")
            }
            .alert("出错了", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("设置宽度比例", isPresented: Binding(
                get: { scaleTarget != nil },
                set: { if !$0 { scaleTarget = nil } }
            )) {
                TextField("0–100", text: $scaleText)
                    .keyboardType(.numberPad)
                Button("确定") {
                    if let v = Double(scaleText), let t = scaleTarget {
                        model.beginChange()
                        model.setFraction(t.id, CGFloat(v / 100))
                    }
                    scaleTarget = nil
                }
                Button("取消", role: .cancel) { scaleTarget = nil }
            } message: {
                Text("相对页面可用宽度的百分比")
            }
            .overlay { statusOverlay }
            .onOpenURL { url in openProject(at: url) }   // 「文件」App → 用 PrintHelper 打开
            .task { ExportService.cleanTempExports() }
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
                Button {
                    scaleText = String(Int((item.widthFraction * 100).rounded()))
                    scaleTarget = item
                } label: {
                    Text("宽度 \(Int((item.widthFraction * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
            }
            Button {
                model.rotate(itemID: item.id)
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.borderless)
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
        // 左：打开工程 / 保存工程（记住上次用的文件夹）
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                openProjectTapped()
            } label: {
                Image(systemName: workspace.hasWorkspace ? "folder.fill" : "folder")
            }
            .accessibilityLabel("打开工程")

            Button {
                saveProjectTapped()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("保存工程")
        }

        // 右：撤销/重做/导入/打印/导出菜单
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

            Button {
                printAllPages()
            } label: {
                Image(systemName: "printer")
            }
            .disabled(model.doc.items.isEmpty)
            .accessibilityLabel("打印全部页")

            Menu {
                exportMenu
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(model.doc.items.isEmpty)
        }
    }

    @ViewBuilder
    private var exportMenu: some View {
        Section("导出（可直接发微信 / 存到文件）") {
            ForEach(ExportKind.allCases) { kind in
                Button {
                    export(kind)
                } label: {
                    Label(kind.label, systemImage: kind.systemImage)
                }
            }
        }
        Divider()
        Button {
            printAllPages()
        } label: {
            Label("打印全部页", systemImage: "printer")
        }
        Divider()
        Button {
            saveProjectTapped()
        } label: {
            Label(workspace.hasWorkspace ? "保存工程到「\(workspace.workspaceName ?? "")」" : "保存工程…",
                  systemImage: "square.and.arrow.down")
        }
        Button {
            openProjectTapped()
        } label: {
            Label("打开工程…", systemImage: "folder")
        }
        if workspace.hasWorkspace {
            Button {
                pickIntent = .pickFolderOnly
                showProjectImporter = true
            } label: {
                Label("更换工程文件夹…", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        Button {
            exportToFilesApp()
        } label: {
            Label("工程另存到「文件」…", systemImage: "doc.badge.arrow.up")
        }
    }

    // MARK: - 工程：打开（带目录缓存）

    private func openProjectTapped() {
        let entries = workspace.projects()
        if workspace.hasWorkspace && !entries.isEmpty {
            showProjectList = true
        } else if workspace.hasWorkspace {
            // 缓存的文件夹是空的 → 直接给系统面板，但也允许换文件夹
            toast("文件夹「\(workspace.workspaceName ?? "")」里还没有工程")
            pickIntent = .openProjectFile
            showProjectImporter = true
        } else {
            pickIntent = .openProjectFile
            showProjectImporter = true
        }
    }

    private var projectListSheet: some View {
        NavigationStack {
            Group {
                let entries = workspace.projects()
                if entries.isEmpty {
                    ContentUnavailableView(
                        "没有工程文件",
                        systemImage: "folder.badge.questionmark",
                        description: Text("「\(workspace.workspaceName ?? "")」里还没有 .phdoc 工程")
                    )
                } else {
                    List(entries) { entry in
                        Button {
                            openProject(at: entry.url)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).font(.body)
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("打开工程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showProjectList = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("换文件夹") {
                        showProjectList = false
                        afterDismiss { pickIntent = .pickFolderToOpen; showProjectImporter = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showProjectList = false
                    afterDismiss { pickIntent = .openProjectFile; showProjectImporter = true }
                } label: {
                    Label("从其他位置打开…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(10)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            switch pickIntent {
            case .openProjectFile:
                openProject(at: url)
            case .pickFolderToSave:
                workspace.rememberWorkspace(url)
                if pendingWrapper != nil {
                    saveName = workspace.suggestedProjectName()
                    showSaveNameAlert = true
                }
            case .pickFolderToOpen:
                workspace.rememberWorkspace(url)
                afterDismiss { showProjectList = true }
            case .pickFolderOnly:
                workspace.rememberWorkspace(url)
                toast("工程文件夹已改为「\(url.lastPathComponent)」")
            }
        case .failure(let error):
            let ns = error as NSError
            // 用户主动取消不提示
            if ns.domain == NSCocoaErrorDomain, ns.code == NSUserCancelledError { return }
            errorMessage = "选择失败：\(error.localizedDescription)"
        }
    }

    private func openProject(at url: URL) {
        guard url.pathExtension == ProjectFile.fileExtension else {
            // 拖进来的是图片 → 直接导入
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                model.importImages(datas: [data])
            } else {
                errorMessage = "无法打开：\(url.lastPathComponent)"
            }
            return
        }
        do {
            let wrapper = try workspace.loadProject(at: url)
            try model.openProject(wrapper)
            showProjectList = false
            toast("已打开 \(url.deletingPathExtension().lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 工程：保存（带目录缓存）

    private func saveProjectTapped() {
        guard !model.doc.items.isEmpty else {
            errorMessage = ExportError.empty.localizedDescription
            return
        }
        do {
            pendingWrapper = try model.saveProject()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
            return
        }
        if workspace.hasWorkspace {
            saveName = workspace.suggestedProjectName()
            showSaveNameAlert = true
        } else {
            // 第一次：先选一个文件夹并缓存，之后就不用再选了
            pickIntent = .pickFolderToSave
            showProjectImporter = true
        }
    }

    private func performSave(_ wrapper: FileWrapper, name: String) {
        do {
            let url = try workspace.saveProject(wrapper, name: name)
            toast("已保存到「\(workspace.workspaceName ?? "")」/\(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 用系统「文件」面板另存一份（不影响缓存的工作文件夹）
    private func exportToFilesApp() {
        guard let wrapper = try? model.saveProject() else {
            errorMessage = "保存失败：无法生成工程文件"
            return
        }
        projectDoc = ProjectDocument(wrapper: wrapper)
        saveName = workspace.suggestedProjectName()
        showProjectExporter = true
    }

    // MARK: - 导出（PDF / PNG / JPG / 长图）

    private func export(_ kind: ExportKind) {
        let doc = model.doc
        busyText = "\(kind.label)…"
        Task.detached(priority: .userInitiated) {
            let result = Result { try ExportService.exportFiles(doc: doc, kind: kind) }
            await MainActor.run {
                busyText = nil
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else {
                        errorMessage = ExportError.renderFailed(kind).localizedDescription
                        return
                    }
                    // 菜单/面板收起动画会和 sheet 抢呈现，稍等一下再弹
                    shareItems = urls
                    afterDismiss { showShare = true }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - 打印（全部页）

    private func printAllPages() {
        guard !model.doc.items.isEmpty else {
            errorMessage = ExportError.empty.localizedDescription
            return
        }
        let doc = model.doc
        let pages = PDFRenderer.pageCount(of: doc)
        busyText = "正在准备打印…"
        Task.detached(priority: .userInitiated) {
            let result = Result { try ExportService.exportFiles(doc: doc, kind: .pdf) }
            await MainActor.run {
                busyText = nil
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        errorMessage = ExportError.renderFailed(.pdf).localizedDescription
                        return
                    }
                    if !Printer.isPrintingAvailable {
                        errorMessage = "当前设备不支持打印（需要 AirPrint）"
                        return
                    }
                    // 打印整份 PDF：系统按页渲染，全部 \(pages) 页都会打出来
                    afterDismiss {
                        Printer.printPDF(at: url, jobName: "作业 (\(pages) 页)") { msg in
                            errorMessage = "打印失败：\(msg)"
                        }
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - 状态浮层

    @ViewBuilder
    private var statusOverlay: some View {
        ZStack {
            VStack {
                Spacer()
                if let toastText {
                    Text(toastText)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            if let busyText {
                ProgressView(busyText)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastText)
        .allowsHitTesting(false)
    }

    private func toast(_ text: String) {
        toastText = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toastText == text { toastText = nil }
        }
    }

    /// 等当前菜单 / sheet 收起后再呈现新内容，避免 SwiftUI 呈现冲突（「点了没反应」）
    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            action()
        }
    }
}

/// 系统分享面板
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad 需要 popover 锚点，否则分享面板弹不出来
        if let popover = vc.popoverPresentationController {
            let host = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
            popover.sourceView = host
            popover.sourceRect = CGRect(x: host?.bounds.midX ?? 0, y: host?.bounds.midY ?? 0, width: 0, height: 0)
        }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
