import SwiftUI

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
        Divider()
        Button("设备与屏幕设置…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("设置…") }
        Button("关于 PadDisplay") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出 PadDisplay") { NSApp.terminate(nil) }
    }
}
