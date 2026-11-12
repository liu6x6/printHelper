#if os(macOS)
import SwiftUI

/// 把文档动作发布到「文件」菜单
struct ExportPDFActionKey: FocusedValueKey { typealias Value = () -> Void }
struct SaveProjectActionKey: FocusedValueKey { typealias Value = () -> Void }
struct OpenProjectActionKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var exportPDFAction: (() -> Void)? {
        get { self[ExportPDFActionKey.self] }
        set { self[ExportPDFActionKey.self] = newValue }
    }
    var saveProjectAction: (() -> Void)? {
        get { self[SaveProjectActionKey.self] }
        set { self[SaveProjectActionKey.self] = newValue }
    }
    var openProjectAction: (() -> Void)? {
        get { self[OpenProjectActionKey.self] }
        set { self[OpenProjectActionKey.self] = newValue }
    }
}

struct DocumentCommands: Commands {
    @FocusedValue(\.openProjectAction) private var openAction
    @FocusedValue(\.saveProjectAction) private var saveAction
    @FocusedValue(\.exportPDFAction) private var exportAction

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("打开工程…") { openAction?() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openAction == nil)
            Button("保存工程…") { saveAction?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(saveAction == nil)
            Divider()
            Button("导出 PDF…") { exportAction?() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(exportAction == nil)
        }
    }
}
#endif