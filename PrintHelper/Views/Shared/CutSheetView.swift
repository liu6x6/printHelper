import SwiftUI

/// 切割面板（C-2/C-7）：拖动一条切割线（横向=上下分 / 纵向=左右分），
/// 实时预览，确认切成两段独立图片。双平台共用。
struct CutSheetView: View {
    let asset: ImageAsset
    let onConfirm: (CGFloat, CutDirection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fraction: CGFloat = 0.5
    @State private var direction: CutDirection = .horizontal
    @State private var dragStart: CGFloat?

    var body: some View {
        VStack(spacing: 14) {
            Text("拖动切割线，图片将分为两段")
                .font(.headline)

            Picker("", selection: $direction) {
                Text("横向 · 上下分").tag(CutDirection.horizontal)
                Text("纵向 · 左右分").tag(CutDirection.vertical)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Text(infoText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            GeometryReader { geo in
                let aspect = max(asset.aspectRatio, 0.01)
                let dw = min(geo.size.width, geo.size.height / aspect)
                let dh = dw * aspect
                let isH = direction == .horizontal
                ZStack(alignment: .topLeading) {
                    if let cg = asset.thumbnail {
                        Image(decorative: cg, scale: 1)
                            .resizable()
                            .frame(width: dw, height: dh)
                    } else {
                        Rectangle().fill(.gray.opacity(0.2)).frame(width: dw, height: dh)
                    }

                    // 第二段轻微压暗，示意将被分开
                    Rectangle()
                        .fill(.black.opacity(0.12))
                        .frame(width: isH ? dw : dw * (1 - fraction),
                               height: isH ? dh * (1 - fraction) : dh)
                        .offset(x: isH ? 0 : dw * fraction, y: isH ? dh * fraction : 0)
                        .allowsHitTesting(false)

                    // 切割线
                    Rectangle()
                        .fill(.red)
                        .frame(width: isH ? dw : 2, height: isH ? 2 : dh)
                        .offset(x: isH ? 0 : dw * fraction - 1, y: isH ? dh * fraction - 1 : 0)
                        .allowsHitTesting(false)

                    // 拖动手柄
                    Capsule()
                        .fill(.red)
                        .frame(width: 52, height: 26)
                        .overlay {
                            Image(systemName: "scissors")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(isH ? 0 : 90))
                        }
                        .shadow(radius: 2)
                        .offset(x: isH ? dw / 2 - 26 : dw * fraction - 26,
                                y: isH ? dh * fraction - 13 : dh / 2 - 13)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if dragStart == nil { dragStart = fraction }
                                    let delta = isH
                                        ? v.translation.height / dh
                                        : v.translation.width / dw
                                    fraction = min(max((dragStart ?? 0.5) + delta, 0.02), 0.98)
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
                    onConfirm(fraction, direction)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 520)
    }

    private var infoText: String {
        let a = Int((fraction * 100).rounded())
        let b = 100 - a
        return direction == .horizontal
            ? "上段 \(a)% · 下段 \(b)%"
            : "左段 \(a)% · 右段 \(b)%"
    }
}