#if os(iOS)
import UIKit

/// iOS AirPrint 打印。
///
/// 关键点：
/// 1. 打印的是**完整 PDF 文件**（临时目录里的 .pdf），系统会按页渲染 → 打印**全部页**，
///    不会像 `printingItem = 单张 UIImage` 那样只出一页；
/// 2. 必须显式给 `printInfo`（jobName / duplex / orientation），
///    否则某些机型上面板弹不出来或作业名为空；
/// 3. iPad 上必须用 `present(from:in:)`（popover 需要锚点），用 `present(animated:)` 会崩/无反应；
/// 4. 从 SwiftUI 的 Menu 里触发时，菜单收起动画会和面板抢呈现，
///    所以统一由顶层 ViewController 呈现，并在失败时回调错误文案（不再静默失败）。
@MainActor
enum Printer {
    /// 打印整份 PDF（所有页）
    /// - Parameters:
    ///   - url: PDF 文件 URL（ExportService 渲染出来的临时文件）
    ///   - jobName: 打印中心显示的任务名，例如「作业 (3 页)」
    ///   - onFail: 失败回调（主线程），用于在界面上提示
    static func printPDF(at url: URL, jobName: String, onFail: @escaping @MainActor (String) -> Void) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            onFail("打印文件不存在，请重新导出")
            return
        }
        guard let host = topViewController() else {
            onFail("找不到当前窗口，无法弹出打印面板")
            return
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general      // 混合内容（图片 + 文本），A4 整页
        info.jobName = jobName
        info.duplex = .longEdge
        info.orientation = .portrait
        controller.printInfo = info
        controller.printingItem = url   // ← 整份 PDF，打印全部页

        // 用户在面板里点取消时 completed = false 但 error = nil，不当作失败
        let completion: UIPrintInteractionController.CompletionHandler = { _, completed, error in
            guard !completed, let error else { return }
            Task { @MainActor in onFail(error.localizedDescription) }
        }

        if host.traitCollection.userInterfaceIdiom == .pad {
            // iPad：popover 需要锚点，取顶部中间一小块区域
            let anchor = CGRect(
                x: host.view.bounds.midX - 60,
                y: host.view.bounds.minY + 80,
                width: 120,
                height: 8
            )
            controller.present(from: anchor, in: host.view, animated: true, completionHandler: completion)
        } else {
            controller.present(animated: true, completionHandler: completion)
        }
    }

    /// 判断当前设备是否能打印（没装 AirPrint 打印机时系统自己会提示）
    static var isPrintingAvailable: Bool { UIPrintInteractionController.isPrintingAvailable }

    /// 当前最顶层的 ViewController（用来呈现打印面板）
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else { return nil }
        let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
#endif
