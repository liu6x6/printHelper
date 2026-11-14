import Foundation
import UniformTypeIdentifiers

/// 导出格式：PDF / 每页 PNG·JPG / 长图 PNG·JPG
enum ExportKind: String, CaseIterable, Identifiable {
    case pdf
    case pagePNG
    case pageJPG
    case longPNG
    case longJPG

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: return "导出 PDF"
        case .pagePNG: return "导出每页 PNG"
        case .pageJPG: return "导出每页 JPG"
        case .longPNG: return "导出长图 PNG"
        case .longJPG: return "导出长图 JPG"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .pagePNG, .pageJPG: return "photo"
        case .longPNG, .longJPG: return "photo.on.rectangle"
        }
    }

    /// 一份文件还是每页一份
    var isSingleFile: Bool {
        switch self {
        case .pdf, .longPNG, .longJPG: return true
        case .pagePNG, .pageJPG: return false
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .pagePNG, .longPNG: return "png"
        case .pageJPG, .longJPG: return "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .pdf: return .pdf
        case .pagePNG, .longPNG: return .png
        case .pageJPG, .longJPG: return .jpeg
        }
    }
}

/// 渲染好的一个导出文件（内存态，还没落盘）
struct RenderedFile {
    let name: String
    let data: Data
}

enum ExportError: LocalizedError {
    case empty
    case renderFailed(ExportKind)

    var errorDescription: String? {
        switch self {
        case .empty: return "当前没有可导出的内容，请先导入图片"
        case .renderFailed(let kind): return "生成\(kind.label.dropFirst(2))失败，图片可能太大或页数太多"
        }
    }
}

/// 导出服务：渲染 + 落盘。
/// 全部为 nonisolated 纯计算，可在后台线程调用（导出时界面不卡、有进度提示）。
enum ExportService {
    static let baseName = "作业"

    /// 渲染成内存数据（每页格式会返回多个）
    static func render(doc: PrintDocument, kind: ExportKind, baseName: String = ExportService.baseName) throws -> [RenderedFile] {
        guard !doc.items.isEmpty else { throw ExportError.empty }
        let pageCount = PDFRenderer.pageCount(of: doc)

        switch kind {
        case .pdf:
            guard let data = PDFRenderer.pdfData(for: doc) else { throw ExportError.renderFailed(kind) }
            return [RenderedFile(name: "\(baseName).pdf", data: data)]

        case .pagePNG, .pageJPG:
            var files: [RenderedFile] = []
            for i in 0..<pageCount {
                let data = kind == .pagePNG
                    ? PDFRenderer.pagePNG(doc: doc, pageIndex: i)
                    : PDFRenderer.pageJPEG(doc: doc, pageIndex: i)
                if let data {
                    let pad = pageCount >= 10 ? String(format: "%02d", i + 1) : "\(i + 1)"
                    files.append(RenderedFile(name: "\(baseName)-第\(pad)页.\(kind.fileExtension)", data: data))
                }
            }
            guard !files.isEmpty else { throw ExportError.renderFailed(kind) }
            return files

        case .longPNG:
            guard let data = PDFRenderer.longImagePNG(doc: doc) else { throw ExportError.renderFailed(kind) }
            return [RenderedFile(name: "\(baseName)-长图.png", data: data)]

        case .longJPG:
            guard let data = PDFRenderer.longImageJPEG(doc: doc) else { throw ExportError.renderFailed(kind) }
            return [RenderedFile(name: "\(baseName)-长图.jpg", data: data)]
        }
    }

    /// 写到临时目录（每次一个独立子目录，避免同名文件被系统缓存），返回可直接分享/打印的 URL
    static func writeTempFiles(_ files: [RenderedFile]) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrintHelper-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try files.map { file in
            let url = dir.appendingPathComponent(file.name)
            try file.data.write(to: url, options: .atomic)
            return url
        }
    }

    /// 一步到位：渲染 + 落盘（后台线程调用）
    static func exportFiles(doc: PrintDocument, kind: ExportKind, baseName: String = ExportService.baseName) throws -> [URL] {
        try writeTempFiles(render(doc: doc, kind: kind, baseName: baseName))
    }

    /// 清理历史临时导出目录（启动时调用，避免 tmp 越堆越大）
    static func cleanTempExports() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        for url in items where url.lastPathComponent.hasPrefix("PrintHelper-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
