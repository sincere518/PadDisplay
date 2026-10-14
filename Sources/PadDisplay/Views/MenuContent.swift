import SwiftUI
import PadDisplayCore

struct MenuContent: View {
    @Bindable var model: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(model.report.busy ? "正在调整屏幕…" : model.sessionState.title, systemImage: model.sessionState.symbol)
        if let active = model.report.active {
            Text("\(active.name.prefix(15)) · \(active.spec.label)").font(.caption)
        }
        Divider()
        Toggle("自动匹配设备", isOn: $model.automatic)
        Button("恢复原桌面") { model.restore() }.disabled(model.report.busy)
        if model.sessionPaused { Button("继续自动匹配") { model.resumeAutomatic() } }
        if !model.favorites.isEmpty {
            Divider()
            ForEach(model.favorites) { profile in
                Button("\(profile.displayTitle.prefix(22))") { model.useManually(profile) }.disabled(model.report.busy)
            }
        }
        if let profile = model.currentProfile {
            Menu("显示预设") {
                ForEach(DesktopDensity.allCases, id: \.self) { density in
                    Button(density.label + (density == profile.density ? " ✓" : "")) { model.setDensity(density, for: profile) }
                }
            }.disabled(model.report.busy)
            Menu("可视区域") {
                ForEach(DisplayRegion.allCases, id: \.self) { region in
                    Button(region.label + (region == profile.region ? " ✓" : "")) { model.setRegion(region, for: profile) }
                }
            }.disabled(model.report.busy)
            Button("切换横竖屏") { model.rotate(profile) }.disabled(model.report.busy)
        }
        Divider()
        Button("设备与屏幕设置…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("设置…") }
        Button("连接助手与诊断…") { openWindow(id: "connection"); NSApp.activate(ignoringOtherApps: true) }
        Button("检查更新…") { model.updates.check(); openWindow(id: "updates"); NSApp.activate(ignoringOtherApps: true) }
        Button("关于 PadDisplay") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出 PadDisplay") { NSApp.terminate(nil) }
    }
}
