import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppController
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Toggle("自动匹配设备", isOn: $model.automatic)
                Text("关闭主窗口后，仍在菜单栏运行。").font(.caption).foregroundStyle(.secondary)
            }
            Section("外观") {
                LabeledContent("跟随系统外观", value: scheme == .dark ? "深色" : "浅色").foregroundStyle(.secondary)
            }
            Section("连接识别") {
                Label(model.permissionGranted ? "已允许识别连接设备" : "允许识别连接设备", systemImage: model.permissionGranted ? "checkmark.shield" : "lock.shield")
                    .font(.headline)
                Text("开启辅助功能权限后，自动识别 UU远程的连接设备。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("打开系统设置") { model.openPermissions() }.appButton(prominent: !model.permissionGranted)
                Text("在系统隐私设置中允许 PadDisplay。部分系统将此项显示为「设备控制和数据访问」。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("也可以先手动应用屏幕配置。").font(.caption).foregroundStyle(.secondary)
            }
            if let notice = model.notice {
                Section { Label(notice, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped).frame(width: 480, height: 460)
    }
}
