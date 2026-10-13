import SwiftUI

struct MenuContent: View {
    @Bindable var model: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.report.busy ? "正在调整屏幕…" : model.report.active == nil ? "等待远程连接" : "远程屏幕已就绪")
        if let active = model.report.active { Text(active.spec.label) }
        Divider()
        Button("设备与屏幕设置…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",")
        Toggle("自动匹配设备", isOn: $model.automatic)
        Button("恢复原桌面") { model.restore() }.disabled(model.report.busy)
        Divider()
        Button("退出 PadDisplay") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
