import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// PrintHelper 工程文件（目录包 .phdoc）
    /// Info.plist 里已声明 com.xiaolong.printhelper.phdoc（UTExportedTypeDeclarations），
    /// 这里优先用正式声明的类型；取不到时才退回临时构造（否则文件面板会把它当普通文件夹）。
    static let phDocument: UTType =
        UTType("com.xiaolong.printhelper.phdoc")
            ?? UTType(filenameExtension: "phdoc", conformingTo: .package)
            ?? .package
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

/// FileWrapper 是引用类型且未标注 Sendable，但工程文档只在主线程读写
extension ProjectDocument: @unchecked Sendable {}