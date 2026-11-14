import Foundation
import Observation
import UniformTypeIdentifiers

/// 工作目录缓存（macOS + iOS 通用）。
///
/// 用「安全作用域书签（security-scoped bookmark）」把用户授权过的目录记进 UserDefaults，
/// 沙盒下这是唯一能跨启动保留目录访问权的方式（iOS 上尤其必要）：
/// - **工程文件夹**：保存工程直接写回这里、打开工程直接列出里面的 `.phdoc`，不用每次重新翻目录；
/// - **导出目录**：导出 PDF / PNG / JPG 时保存面板直接定位到上次的目录；
/// - **导入目录**：导入图片时打开面板直接定位到上次的目录。
///
/// 书签不可用时（非沙盒构建、模拟器等）自动退回「只记路径」。
@MainActor
@Observable
final class WorkspaceStore {
    static let shared = WorkspaceStore()

    /// 工作文件夹里的一个工程文件
    struct ProjectEntry: Identifiable, Hashable {
        let url: URL
        var modified: Date?
        var byteSize: Int = 0
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }

        var detail: String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            let date = modified.map { f.string(from: $0) } ?? "—"
            let mb = Double(byteSize) / 1_048_576
            return mb >= 1 ? "\(date) · \(String(format: "%.1f", mb)) MB" : "\(date) · \(byteSize / 1024) KB"
        }
    }

    enum WorkspaceError: LocalizedError {
        case noFolder
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noFolder: return "还没有选择工作文件夹"
            case .failed(let m): return m
            }
        }
    }

    /// 一类被缓存的目录
    private struct CachedDir {
        let bookmarkKey: String
        let pathKey: String
    }

    private static let workspaceKeys = CachedDir(
        bookmarkKey: "PrintHelper.workspaceBookmark", pathKey: "PrintHelper.workspacePath")
    private static let exportKeys = CachedDir(
        bookmarkKey: "PrintHelper.exportDirBookmark", pathKey: "PrintHelper.exportDirPath")
    private static let importKeys = CachedDir(
        bookmarkKey: "PrintHelper.importDirBookmark", pathKey: "PrintHelper.importDirPath")
    private static let lastProjectKey = "PrintHelper.lastProjectPath"

    private let defaults: UserDefaults

    /// 缓存的「工程文件夹」
    private(set) var workspaceURL: URL?
    /// 缓存的「导出目录」（PDF / 图片）
    private(set) var exportDirURL: URL?
    /// 缓存的「图片导入目录」
    private(set) var importDirURL: URL?
    /// 上次打开的工程路径（仅展示用，访问权靠所在目录）
    private(set) var lastProjectPath: String?

    var hasWorkspace: Bool { workspaceURL != nil }
    var workspaceName: String? { workspaceURL?.lastPathComponent }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workspaceURL = Self.restore(Self.workspaceKeys, defaults: defaults)
        exportDirURL = Self.restore(Self.exportKeys, defaults: defaults)
        importDirURL = Self.restore(Self.importKeys, defaults: defaults)
        lastProjectPath = defaults.string(forKey: Self.lastProjectKey)
    }

    // MARK: - 记住目录

    /// 记住工程文件夹（用户刚在文件面板里选中的目录 / 刚保存过工程的目录）
    func rememberWorkspace(_ url: URL) {
        workspaceURL = persist(url, Self.workspaceKeys)
    }

    /// 记住导出目录（可传文件 URL，自动取所在目录）
    func rememberExportDir(_ url: URL) {
        exportDirURL = persist(url, Self.exportKeys)
    }

    /// 记住图片导入目录
    func rememberImportDir(_ url: URL) {
        importDirURL = persist(url, Self.importKeys)
    }

    /// 清除工程文件夹缓存（下次保存/打开重新选）
    func clearWorkspace() {
        workspaceURL = nil
        defaults.removeObject(forKey: Self.workspaceKeys.bookmarkKey)
        defaults.removeObject(forKey: Self.workspaceKeys.pathKey)
    }

    // MARK: - 安全作用域访问

    /// 在安全作用域内使用工作文件夹（没有缓存目录时返回 nil）
    func withWorkspace<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let url = workspaceURL else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// 同 withWorkspace，但没有缓存目录时也会回调（参数为 nil）—— macOS 面板要先设 directoryURL
    func withWorkspaceDir<T>(_ body: (URL?) throws -> T) rethrows -> T {
        try scoped(workspaceURL, body)
    }

    /// 在安全作用域内使用导出目录（可能为 nil）
    func withExportDir<T>(_ body: (URL?) throws -> T) rethrows -> T {
        try scoped(exportDirURL, body)
    }

    /// 在安全作用域内使用图片导入目录（可能为 nil）
    func withImportDir<T>(_ body: (URL?) throws -> T) rethrows -> T {
        try scoped(importDirURL, body)
    }

    private func scoped<T>(_ url: URL?, _ body: (URL?) throws -> T) rethrows -> T {
        guard let url else { return try body(nil) }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    // MARK: - 工程：保存 / 列举 / 打开

    /// 直接把工程写进缓存的工程文件夹，返回写入的 URL
    @discardableResult
    func saveProject(_ wrapper: FileWrapper, name: String) throws -> URL {
        guard let dir = workspaceURL else { throw WorkspaceError.noFolder }
        let scoped = dir.startAccessingSecurityScopedResource()
        defer { if scoped { dir.stopAccessingSecurityScopedResource() } }

        let base = Self.sanitized(name, fallback: "作业")
        let fileName = base.hasSuffix(".\(ProjectFile.fileExtension)")
            ? base
            : "\(base).\(ProjectFile.fileExtension)"
        let url = Self.uniqueURL(dir.appendingPathComponent(fileName))

        wrapper.preferredFilename = fileName
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)   // 目录包要先删旧的
            }
            try wrapper.write(to: url, options: [.atomic], originalContentsURL: nil)
        } catch {
            throw WorkspaceError.failed("写入失败：\(error.localizedDescription)")
        }
        rememberLastProject(url)
        return url
    }

    /// 工作文件夹里的全部 .phdoc 工程（按修改时间倒序）
    func projects() -> [ProjectEntry] {
        withWorkspace { dir -> [ProjectEntry] in
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { return [] }
            return urls
                .filter { $0.pathExtension == ProjectFile.fileExtension }
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    return ProjectEntry(
                        url: url,
                        modified: values?.contentModificationDate,
                        byteSize: values?.fileSize ?? 0
                    )
                }
                .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        } ?? []
    }

    /// 读取任意位置的工程（文件面板选中的 / 「打开方式」传进来的 URL）
    func loadProject(at url: URL) throws -> FileWrapper {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let wrapper = try FileWrapper(url: url, options: .immediate)
            rememberLastProject(url)
            // 顺便把这个文件所在目录记成工程文件夹，下次直接列出
            rememberWorkspace(url.deletingLastPathComponent())
            return wrapper
        } catch {
            throw WorkspaceError.failed("读取失败：\(error.localizedDescription)")
        }
    }

    /// 默认工程名：作业 / 作业 2 / …（避免覆盖已有文件）
    func suggestedProjectName() -> String {
        let existing = Set(projects().map(\.name))
        guard existing.contains("作业") else { return "作业" }
        var i = 2
        while existing.contains("作业 \(i)") { i += 1 }
        return "作业 \(i)"
    }

    private func rememberLastProject(_ url: URL) {
        lastProjectPath = url.path
        defaults.set(url.path, forKey: Self.lastProjectKey)
    }

    // MARK: - Private（书签读写）

    private func persist(_ url: URL, _ dir: CachedDir) -> URL {
        let target = Self.directoryPart(of: url)
        // 书签失败（非沙盒等）就退回记路径，至少目录定位还能用
        if let data = Self.bookmark(for: target) {
            defaults.set(data, forKey: dir.bookmarkKey)
        } else {
            defaults.removeObject(forKey: dir.bookmarkKey)
        }
        defaults.set(target.path, forKey: dir.pathKey)
        return target
    }

    private static func restore(_ dir: CachedDir, defaults: UserDefaults) -> URL? {
        if let resolved = resolve(defaults.data(forKey: dir.bookmarkKey)) {
            if resolved.isStale, let data = bookmark(for: resolved.url) {
                defaults.set(data, forKey: dir.bookmarkKey)
            }
            return resolved.url
        }
        guard let path = defaults.string(forKey: dir.pathKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolve(_ data: Data?) -> (url: URL, isStale: Bool)? {
        guard let data, !data.isEmpty else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: bookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }

    /// macOS 沙盒需要显式声明安全作用域；iOS 上文档选择器给的书签默认就是安全作用域的
    /// （`.withSecurityScope` 在 iOS 不可用）。
    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return .withSecurityScope
        #else
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    /// 传文件就取所在目录，传目录就原样返回
    private static func directoryPart(of url: URL) -> URL {
        url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    }

    /// 去掉路径分隔符等非法字符
    private static func sanitized(_ name: String, fallback: String) -> String {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// 同名文件已存在时自动加序号：作业.phdoc → 作业 2.phdoc
    private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 2
        while i < 10_000 {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
        return url
    }
}
