import PadDisplayCore
import SwiftUI

struct DeviceDetailView: View {
    var model: AppController
    var profile: DeviceProfile
    var edit: (DeviceProfile) -> Void

    private var live: Bool {
        model.report.active?.name == profile.name && !model.report.failed && !model.report.busy
    }
    private var spec: DisplaySpec { live ? model.report.active!.spec : profile.spec }
    private var validSize: Bool { spec.validationError == nil }
    private var connected: Bool { model.controllers.contains(profile.name) }
    private var status: String {
        if live { return model.manualMode ? "手动屏幕已就绪" : "屏幕已就绪" }
        return connected ? "已连接 · 配置预览" : "未连接 · 配置预览"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { title; badge }
                    VStack(alignment: .leading, spacing: 10) { title; badge }
                }
                Text(live ? (model.manualMode ? "手动配置已应用；恢复后可继续自动匹配。" : "已自动应用此设备的屏幕配置。") : "查看保存的配置，不会切换当前正在使用的屏幕。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 36) {
                DevicePreview(spec: spec, symbol: profile.symbol)
                    .frame(width: 260, height: 190).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 18) {
                    metric(live ? "输出像素" : "保存的输出像素", value: validSize ? spec.label : "尚未设置")
                    metric("桌面尺寸", value: validSize ? "\(spec.width / (spec.hiDPI ? 2 : 1)) × \(spec.height / (spec.hiDPI ? 2 : 1))" : "确认尺寸后显示")
                    HStack(spacing: 12) {
                        Label(spec.hiDPI ? "HiDPI 已开启" : "标准像素", systemImage: "sparkles")
                        if live { Label("当前主显示器", systemImage: "checkmark.circle") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if live {
                HStack(spacing: 12) {
                    Image(systemName: "display").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("在 UU远程中选择「PadDisplay」屏幕").font(.callout.weight(.medium))
                        Text("屏幕已匹配；连接端可能需要切换一次显示器。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(14).groupedSurface()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("保存的配置").font(.headline)
                    Spacer()
                    Button("编辑配置…") { edit(profile) }.appButton()
                }
                VStack(spacing: 0) {
                    summary("屏幕型号", value: validSize ? profile.presetLabel : "尚未确认尺寸")
                    Divider().padding(.horizontal, 16)
                    summary("屏幕方向", value: validSize ? (profile.spec.width >= profile.spec.height ? "横屏" : "竖屏") : "—")
                    Divider().padding(.horizontal, 16)
                    HStack {
                        Text("连接时自动调整")
                        Spacer()
                        Toggle("连接时自动调整", isOn: Binding(get: { profile.enabled }, set: { enabled in
                            var changed = profile
                            changed.enabled = enabled
                            if enabled, changed.spec.validationError != nil { edit(changed) }
                            else { model.save(changed) }
                        })).labelsHidden().accessibilityLabel("连接时自动调整")
                            .toggleStyle(.switch).controlSize(.small).disabled(model.report.busy)
                    }.font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                }.groupedSurface()
                Text("断开自动匹配的连接后，恢复原桌面。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Label("配置已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                Spacer()
                Button("立即应用") { model.useManually(profile) }.appButton()
                    .disabled(!profile.enabled || !validSize || model.report.busy || model.companionRunning)
                    .help("手动应用此配置，直到恢复、继续自动匹配或退出。")
            }.font(.callout)
        }
    }

    private var title: some View {
        Text(profile.displayTitle).font(.system(size: 28, weight: .semibold)).textSelection(.enabled)
            .accessibilityLabel(profile.displayTitle)
    }
    private var badge: some View {
        Label(status, systemImage: live ? "circle.fill" : "circle")
            .font(.caption.weight(.medium)).foregroundStyle(live ? Color.green : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((live ? Color.green : Color.secondary).opacity(0.1), in: Capsule())
    }
    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: validSize ? 28 : 20, weight: .semibold)).monospacedDigit().textSelection(.enabled)
        }.accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value)
    }
    private func summary(_ label: String, value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
            .font(.callout).padding(.horizontal, 16).padding(.vertical, 11)
    }
}

private struct DevicePreview: View {
    var spec: DisplaySpec
    var symbol: String
    @Environment(\.colorScheme) private var scheme
    private static let phoneFrame = Bundle.main.url(forResource: "iphone-frame", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if spec.validationError == nil {
            if symbol == "iphone", let frame = Self.phoneFrame {
                PhonePreview(frame: frame)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(scheme == .dark ? 0.6 : 0.9))
                    PreviewWallpaper().clipShape(RoundedRectangle(cornerRadius: 6)).padding(9)
                }
                .aspectRatio(CGFloat(spec.width) / CGFloat(spec.height), contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        } else {
            Image(systemName: symbol).font(.system(size: 76, weight: .ultraLight)).foregroundStyle(.secondary)
        }
    }
}

private struct PhonePreview: View {
    var frame: NSImage

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            // 素材为 1311 × 2708；透明屏幕开口为 (52, 42, 1208, 2624)。
            let screenWidth = w * 1208 / 1311
            let screenHeight = h * 2624 / 2708
            ZStack(alignment: .topLeading) {
                PreviewWallpaper()
                    .frame(width: screenWidth, height: screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: w * 0.13))
                    .offset(x: w * 52 / 1311, y: h * 42 / 2708)
                Image(nsImage: frame).resizable().frame(width: w, height: h)
            }.frame(width: w, height: h)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.aspectRatio(1311.0 / 2708, contentMode: .fit)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
    }
}
