import Foundation

/// 工程文件（.phdoc）：目录包 = document.json 清单 + assets/ 原始图片数据。
/// 保存完整可编辑状态：图片、位置、缩放、切割结果、页面设置（S-1）。
enum ProjectFileError: Error {
    case invalidFormat
    case missingManifest
    case missingAsset(UUID)
}

struct ProjectManifest: Codable {
    var version: Int = 1
    var layoutMode: String  // "free" | "flow"
    var margin: CGFloat
    var pageCount: Int
    var items: [ItemRecord]
    var assets: [AssetRecord]

    struct ItemRecord: Codable {
        var id: UUID
        var assetID: UUID
        var widthFraction: CGFloat
        var pageIndex: Int
        var originX: CGFloat
        var originY: CGFloat
    }

    struct AssetRecord: Codable {
        var id: UUID
        var file: String
    }
}

enum ProjectFile {
    static let fileExtension = "phdoc"

    static func archive(_ doc: PrintDocument) throws -> FileWrapper {
        let assetsDir = FileWrapper(directoryWithFileWrappers: [:])
        assetsDir.preferredFilename = "assets"
        var assetRecords: [ProjectManifest.AssetRecord] = []
        for (id, asset) in doc.assets.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let filename = "\(id.uuidString).img"
            assetsDir.addRegularFile(withContents: asset.data, preferredFilename: filename)
            assetRecords.append(.init(id: id, file: filename))
        }

        let manifest = ProjectManifest(
            layoutMode: doc.layoutMode == .free ? "free" : "flow",
            margin: doc.settings.margin,
            pageCount: doc.pageCount,
            items: doc.items.map {
                .init(id: $0.id, assetID: $0.assetID, widthFraction: $0.widthFraction,
                      pageIndex: $0.pageIndex, originX: $0.origin.x, originY: $0.origin.y)
            },
            assets: assetRecords
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)

        let root = FileWrapper(directoryWithFileWrappers: [:])
        root.preferredFilename = "document.\(fileExtension)"
        root.addRegularFile(withContents: manifestData, preferredFilename: "document.json")
        root.addFileWrapper(assetsDir)
        return root
    }

    static func load(_ wrapper: FileWrapper) throws -> PrintDocument {
        guard wrapper.isDirectory,
              let manifestData = wrapper.fileWrappers?["document.json"]?.regularFileContents else {
            throw ProjectFileError.missingManifest
        }
        let manifest = try JSONDecoder().decode(ProjectManifest.self, from: manifestData)
        guard manifest.version == 1 else { throw ProjectFileError.invalidFormat }

        var doc = PrintDocument(layoutMode: manifest.layoutMode == "free" ? .free : .flow)
        doc.settings.margin = manifest.margin
        doc.pageCount = max(1, manifest.pageCount)

        let assetsDir = wrapper.fileWrappers?["assets"]
        for record in manifest.assets {
            guard let data = assetsDir?.fileWrappers?[record.file]?.regularFileContents else {
                throw ProjectFileError.missingAsset(record.id)
            }
            doc.assets[record.id] = ImageAsset(id: record.id, data: data)
        }
        doc.items = manifest.items.map { record in
            var item = ImageItem(id: record.id, assetID: record.assetID)
            item.widthFraction = record.widthFraction
            item.pageIndex = record.pageIndex
            item.origin = CGPoint(x: record.originX, y: record.originY)
            return item
        }
        return doc
    }
}