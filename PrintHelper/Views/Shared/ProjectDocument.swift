import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// PrintHelper 工程文件（目录包 .phdoc）
    static let phDocument = UTType(filenameExtension: "phdoc", conformingTo: .package) ?? .package
}

/// 可编辑工程文件（macOS / iOS 共用）
struct ProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.phDocument] }

    var wrapper: FileWrapper

    init(wrapper: FileWrapper) {
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        guard configuration.file.isDirectory else {
            throw CocoaError(.fileReadCorruptFile)
        }
        wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}