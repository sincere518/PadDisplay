import SwiftUI

/// 原创比例自适应壁纸，仅用于设备预览。
struct PreviewWallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        LinearGradient(colors: dark ? [Color(red: 0.04, green: 0.09, blue: 0.22), .indigo.opacity(0.7)] :
            [Color(red: 0.83, green: 0.93, blue: 1), Color(red: 0.38, green: 0.59, blue: 0.9)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay {
            Canvas { context, size in
                let w = size.width, h = size.height
                var lower = Path()
                lower.move(to: CGPoint(x: -0.1 * w, y: 0.32 * h))
                lower.addCurve(to: CGPoint(x: 1.1 * w, y: 0.8 * h),
                               control1: CGPoint(x: 0.4 * w, y: 0.17 * h), control2: CGPoint(x: 0.31 * w, y: 1.11 * h))
                lower.addLine(to: CGPoint(x: 1.1 * w, y: 1.1 * h))
                lower.addLine(to: CGPoint(x: -0.1 * w, y: 1.1 * h))
                lower.closeSubpath()
                context.fill(lower, with: .linearGradient(Gradient(colors: dark ?
                    [Color(red: 0.12, green: 0.28, blue: 0.56), Color(red: 0.2, green: 0.18, blue: 0.5)] :
                    [Color(red: 0.21, green: 0.51, blue: 0.91), Color(red: 0.34, green: 0.35, blue: 0.76)]),
                    startPoint: .zero, endPoint: CGPoint(x: w, y: h)))

                var fold = Path()
                fold.move(to: CGPoint(x: -0.05 * w, y: 0.27 * h))
                fold.addCurve(to: CGPoint(x: 0.54 * w, y: 0.62 * h),
                              control1: CGPoint(x: 0.18 * w, y: 0.12 * h), control2: CGPoint(x: 0.26 * w, y: 0.58 * h))
                fold.addCurve(to: CGPoint(x: 1.05 * w, y: -0.1 * h),
                              control1: CGPoint(x: 0.89 * w, y: 0.66 * h), control2: CGPoint(x: 0.73 * w, y: 0.08 * h))
                fold.addLine(to: CGPoint(x: 0.7 * w, y: -0.1 * h))
                fold.addCurve(to: CGPoint(x: -0.05 * w, y: 0.27 * h),
                              control1: CGPoint(x: 0.63 * w, y: 0.31 * h), control2: CGPoint(x: 0.35 * w, y: 0.42 * h))
                fold.closeSubpath()
                context.fill(fold, with: .linearGradient(Gradient(colors: dark ?
                    [Color(red: 0.36, green: 0.62, blue: 0.86).opacity(0.75), Color(red: 0.13, green: 0.3, blue: 0.65)] :
                    [Color(red: 0.96, green: 0.99, blue: 1).opacity(0.9), Color(red: 0.59, green: 0.8, blue: 1)]),
                    startPoint: CGPoint(x: 0, y: h * 0.2), endPoint: CGPoint(x: w, y: h * 0.65)))

                var highlight = Path()
                highlight.move(to: CGPoint(x: -0.05 * w, y: 0.28 * h))
                highlight.addCurve(to: CGPoint(x: 0.54 * w, y: 0.62 * h),
                                   control1: CGPoint(x: 0.18 * w, y: 0.13 * h), control2: CGPoint(x: 0.26 * w, y: 0.58 * h))
                highlight.addCurve(to: CGPoint(x: 1.05 * w, y: -0.1 * h),
                                   control1: CGPoint(x: 0.89 * w, y: 0.66 * h), control2: CGPoint(x: 0.73 * w, y: 0.08 * h))
                context.stroke(highlight, with: .color(.white.opacity(dark ? 0.12 : 0.35)), lineWidth: 0.7)
            }
        }.clipped()
    }
}
