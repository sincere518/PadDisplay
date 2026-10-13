// 首次启动功能导览（TourKit）：5 页说明 + 配图；首次启动先看导览，再进权限引导与设备配置
// 配图由 `UUDisplay --render-tour <目录>` 用下方 SwiftUI 插画渲染为 16:10 PNG（Assets/Tour），打包时拷进 Contents/Resources
import AppKit
import SwiftUI
import TourKit

enum Tour {
    static let pages: [(image: String, title: LocalizedStringKey, description: LocalizedStringKey)] = [
        ("tour-welcome", "欢迎使用 UU远程伴侣",
         "用平板或手机通过 UU远程 操控这台 Mac 时，它会自动准备一块和你的设备尺寸完全一致的屏幕。"),
        ("tour-match", "一连上，画面就刚好铺满",
         "认出连进来的是哪台设备，几秒内换上合适的屏幕，没有黑边、文字清晰；断开后一切恢复原样。"),
        ("tour-physical", "远程时只留一块屏幕",
         "可以在设置里打开：远程期间暂时熄灭 Mac 自己的屏幕和外接显示器，窗口不会跑到你看不见的地方。用电脑连接时不受影响。"),
        ("tour-safety", "万一出问题，也能马上找回",
         "坐在 Mac 前按 ⌃ control + ⌥ option + ⌘ command + 9，所有屏幕立刻亮起来；还可以打开后台守护自动照看；重启 Mac 也一定能恢复。"),
        ("tour-setup", "还差两步就能用了",
         "先允许它读取设备名称，再确认每台设备的屏幕尺寸。之后随时可以点菜单栏图标修改设置，或再看一遍介绍。"),
    ]

    static let artworks: [String: AnyView] = [
        "tour-welcome": AnyView(WelcomeArt()),
        "tour-match": AnyView(MatchArt()),
        "tour-physical": AnyView(PhysicalArt()),
        "tour-safety": AnyView(SafetyArt()),
        "tour-setup": AnyView(SetupArt()),
    ]

    /// 调试：把 TourKit 导览界面逐页渲染为 PNG（配图取自 imagesDir，即 Assets/Tour）
    @MainActor
    static func renderUI(imagesDir: URL, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = Bundle(url: imagesDir)
        let tourPages = pages.map { TourPage(imageName: $0.image, imageBundle: bundle, title: $0.title, description: $0.description) }
        for i in tourPages.indices {
            let view = TourSlideshowView(pages: tourPages, width: 660, initialPageIndex: i,
                                         continueButtonTitle: "继续", finishButtonTitle: "开始设置")
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
            let url = dir.appendingPathComponent("page-\(i + 1).png")
            try? png.write(to: url)
            print("✅ \(url.path)")
        }
    }

    /// 调试：把配图渲染为 1600×1000 PNG（800×500 pt @2x）
    @MainActor
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, view) in artworks {
            let renderer = ImageRenderer(content: view.frame(width: 800, height: 500))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                print("❌ 渲染失败 \(name)")
                continue
            }
            let url = dir.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print("✅ \(url.path)")
        }
    }
}

@MainActor
final class TourController {
    private let window = TourKitWindowController()

    /// 展示导览；关闭或完成后调用 onDone（仅一次）
    func show(onDone: (() -> Void)? = nil) {
        var called = false
        let done = {
            guard !called else { return }
            called = true
            ConfigStore.shared.config.tourShown = true
            onDone?()
        }
        window.present(
            pages: Tour.pages.map { TourPage(imageName: $0.image, imageBundle: .main, title: $0.title, description: $0.description) },
            width: 660,
            continueButtonTitle: "继续",
            finishButtonTitle: "开始设置",
            onFinish: done,
            onClose: done
        )
    }
}

// MARK: - 配图（800×500 pt，顶部亮、底部渐暗以衔接 TourKit 的深色文字区）

private let accent = LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.55, green: 0.40, blue: 1.0)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)

private struct ArtBackground<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.04, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(0.45), .clear], center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 420)
            content.offset(y: -20)
        }
        .frame(width: 800, height: 500)
        .clipped()
    }
}

/// 带边框的设备屏幕
private struct Screen<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 14
    var bezel: CGFloat = 8
    var lit = true
    @ViewBuilder let content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(white: 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: radius - bezel / 2, style: .continuous)
                    .fill(lit ? AnyShapeStyle(accent.opacity(0.9)) : AnyShapeStyle(Color(white: 0.07)))
                    .overlay(content)
                    .padding(bezel)
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .frame(width: width, height: height)
            .shadow(color: lit ? Color.blue.opacity(0.45) : .clear, radius: 24)
    }
}

private struct Monitor: View {
    var lit = true
    var body: some View {
        VStack(spacing: 0) {
            Screen(width: 300, height: 180, lit: lit) {
                if !lit {
                    Image(systemName: "power").font(.system(size: 34, weight: .semibold)).foregroundStyle(Color(white: 0.35))
                }
            }
            Rectangle().fill(Color(white: 0.22)).frame(width: 34, height: 34)
            Capsule().fill(Color(white: 0.24)).frame(width: 120, height: 8)
        }
    }
}

private struct Laptop: View {
    var lit = true
    var body: some View {
        VStack(spacing: 0) {
            Screen(width: 200, height: 128, radius: 10, bezel: 6, lit: lit) {
                if !lit {
                    Image(systemName: "power").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color(white: 0.35))
                }
            }
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(Color(white: 0.24)).frame(width: 236, height: 10)
        }
    }
}

private struct Chip: View {
    let text: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

private struct WelcomeArt: View {
    var body: some View {
        ArtBackground(tint: .blue) {
            HStack(alignment: .bottom, spacing: 46) {
                Screen(width: 190, height: 132, radius: 16, bezel: 9) {
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(.bottom, 30)
                Image(systemName: "dot.radiowaves.right")
                    .font(.system(size: 44, weight: .semibold)).foregroundStyle(accent)
                    .padding(.bottom, 92)
                Monitor()
            }
        }
    }
}

private struct MatchArt: View {
    var body: some View {
        ArtBackground(tint: .purple) {
            HStack(spacing: 40) {
                VStack(spacing: 14) {
                    Screen(width: 216, height: 150, radius: 16, bezel: 9) {}
                    Chip(text: "iPad Air 11″")
                }
                Image(systemName: "arrow.right").font(.system(size: 36, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                VStack(spacing: 14) {
                    Screen(width: 300, height: 208) {
                        VStack(spacing: 6) {
                            Text("2360 × 1640").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("高清").font(.system(size: 15, weight: .semibold, design: .rounded)).opacity(0.85)
                        }
                        .foregroundStyle(.white)
                    }
                    Chip(text: "铺满 · 无黑边", symbol: "checkmark.circle.fill")
                }
            }
        }
    }
}

private struct PhysicalArt: View {
    var body: some View {
        ArtBackground(tint: .indigo) {
            VStack(spacing: 26) {
                VStack(spacing: 12) {
                    Screen(width: 230, height: 160, radius: 16, bezel: 9) {
                        Image(systemName: "ipad.landscape").font(.system(size: 54)).foregroundStyle(.white)
                    }
                    Chip(text: "只留虚拟屏幕", symbol: "sparkles")
                }
                HStack(alignment: .bottom, spacing: 40) {
                    Laptop(lit: false)
                    Monitor(lit: false)
                }
                .scaleEffect(0.62)
                .frame(height: 150)
                .opacity(0.8)
            }
            .offset(y: 10)
        }
    }
}

private struct KeyCap: View {
    let label: String
    /// 修饰键的英文名（照顾不熟悉符号的新用户）
    var name: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: name == nil ? 40 : 34, weight: .medium, design: .rounded))
            if let name { Text(name).font(.system(size: 14, weight: .medium)) }
        }
            .foregroundStyle(.white)
            .frame(width: name == nil ? 84 : 104, height: 84)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.20)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 5)
    }
}

private struct SafetyArt: View {
    var body: some View {
        ArtBackground(tint: .teal) {
            VStack(spacing: 30) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(accent)
                    .shadow(color: .blue.opacity(0.6), radius: 20)
                HStack(spacing: 14) {
                    KeyCap(label: "⌃", name: "control")
                    KeyCap(label: "⌥", name: "option")
                    KeyCap(label: "⌘", name: "command")
                    KeyCap(label: "9")
                }
            }
        }
    }
}

private struct SetupArt: View {
    private struct Row: View {
        let symbol: String
        let title: String
        var body: some View {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(accent).frame(width: 40)
                Text(title).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "circle").font(.system(size: 26)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .frame(width: 420, height: 78)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    var body: some View {
        ArtBackground(tint: .blue) {
            VStack(spacing: 18) {
                Row(symbol: "hand.raised.fill", title: "允许读取设备名称")
                Row(symbol: "rectangle.on.rectangle", title: "确认屏幕尺寸")
            }
        }
    }
}
