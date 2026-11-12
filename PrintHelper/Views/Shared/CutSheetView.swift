import SwiftUI

/// 切割面板（C-2）：拖动一条水平切割线，实时预览，确认切成上下两段。
/// 双平台共用。
struct CutSheetView: View {
    let asset: ImageAsset
    let onConfirm: (CGFloat) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fraction: CGFloat = 0.5
    @State private var dragStart: CGFloat?

    var body: some View {
        VStack(spacing: 16) {
            Text("拖动切割线，图片将分为上下两段")
                .font(.headline)
            Text("上段 \(Int((fraction * 100).rounded()))% · 下段 \(Int(((1 - fraction) * 100).rounded()))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            GeometryReader { geo in
                let aspect = max(asset.aspectRatio, 0.01)
                let dw = min(geo.size.width, geo.size.height / aspect)
                let dh = dw * aspect
                ZStack(alignment: .topLeading) {
                    if let cg = asset.thumbnail {
                        Image(decorative: cg, scale: 1)
                            .resizable()
                            .frame(width: dw, height: dh)
                    } else {
                        Rectangle().fill(.gray.opacity(0.2)).frame(width: dw, height: dh)
                    }

                    // 下半段轻微压暗，示意将被分开
                    Rectangle()
                        .fill(.black.opacity(0.12))
                        .frame(width: dw, height: dh * (1 - fraction))
                        .offset(y: dh * fraction)
                        .allowsHitTesting(false)

                    // 切割线
                    Rectangle()
                        .fill(.red)
                        .frame(width: dw, height: 2)
                        .offset(y: dh * fraction - 1)
                        .allowsHitTesting(false)

                    // 拖动手柄
                    Capsule()
                        .fill(.red)
                        .frame(width: 52, height: 26)
                        .overlay {
                            Image(systemName: "scissors")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .shadow(radius: 2)
                        .offset(x: dw / 2 - 26, y: dh * fraction - 13)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if dragStart == nil { dragStart = fraction }
                                    let f = (dragStart ?? 0.5) + v.translation.height / dh
                                    fraction = min(max(f, 0.02), 0.98)
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                }
                .frame(width: dw, height: dh)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }

            HStack(spacing: 16) {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("确认切割") {
                    onConfirm(fraction)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 480)
    }
}