#if os(macOS)
import SwiftUI

/// 把「导出 PDF」动作发布到菜单（文件菜单 → 导出 PDF… ⌘E）
struct ExportPDFActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var exportPDFAction: (() -> Void)? {
        get { self[ExportPDFActionKey.self] }
        set { self[ExportPDFActionKey.self] = newValue }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.exportPDFAction) private var exportAction

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("导出 PDF…") { exportAction?() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(exportAction == nil)
        }
    }
}
#endif