import SwiftUI

/// 只读页面预览（iOS 预览 / 通用缩略场景）
struct PagePreviewView: View {
    let doc: PrintDocument
    let entries: [LayoutEngine.Entry]
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
            ForEach(entries, id: \.item.id) { entry in
                if let asset = doc.assets[entry.item.assetID], let cg = asset.thumbnail {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .frame(width: entry.frame.width * scale,
                               height: entry.frame.height * scale)
                        .offset(x: entry.frame.minX * scale, y: entry.frame.minY * scale)
                }
            }
        }
        .frame(width: A4.width * scale, height: A4.height * scale)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5))
    }
}