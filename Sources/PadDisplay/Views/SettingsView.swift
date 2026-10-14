import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TabView {
          Form {
            Section("通用") {
                Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Toggle("自动匹配设备", isOn: $model.automatic)
                Toggle("恢复原桌面时还原窗口位置", isOn: $model.restoreWindowPositions)
                Text("还原仍存在的普通窗口。全屏、最小化或受保护窗口可能由应用自行管理。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("关闭主窗口后，仍在菜单栏运行。").font(.caption).foregroundStyle(.secondary)
            }
            Section("快捷操作") {
                Toggle("启用全局快捷键", isOn: $model.shortcutsEnabled)
                Text("⌃⌥⌘1–9 应用菜单栏收藏；⌃⌥⌘0 恢复原桌面；⌃⌥⌘R 切换当前设备方向。")
                    .font(.callout).foregroundStyle(.secondary)
                if let problem = model.shortcutProblem { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                Text("右键设备可复制快捷指令链接，配合「快捷指令」的「打开 URL」动作使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
          }.formStyle(.grouped).tabItem { Label("通用", systemImage: "gearshape") }
          Form {
            Section("连接识别") {
                Label(model.permissionGranted ? "已允许识别连接设备" : "允许识别连接设备", systemImage: model.permissionGranted ? "checkmark.shield" : "lock.shield")
                    .font(.headline)
                Text("用于读取 UU远程的连接表格，以及按设置还原普通窗口位置。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("打开系统设置") { model.openPermissions() }.appButton(prominent: !model.permissionGranted)
                Text("在系统隐私设置中允许 PadDisplay。部分系统将此项显示为「设备控制和数据访问」。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("也可以先手动应用屏幕配置。").font(.caption).foregroundStyle(.secondary)
            }
            Section("连接助手") {
                Text("检查权限、连接设备、配置、实际屏幕与桌面恢复状态。")
                Button("打开连接助手与诊断") { openWindow(id: "connection") }.appButton()
            }
          }.formStyle(.grouped).tabItem { Label("连接", systemImage: "network") }
          Form {
            Section("设备配置") {
                LabeledContent("保存的设备", value: "\(model.profiles.count) 台")
                Text("导出包含屏幕身份、像素、显示预设、可视区域、用途和收藏。不会导出权限、账号或窗口记录。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("导出配置…") { model.exportProfiles() }.appButton().disabled(model.profiles.isEmpty)
                    Button("导入配置…") { model.importProfiles() }.appButton().disabled(model.report.busy)
                }
                Text("导入前会预览，并自动备份本机原配置。合并时同名设备保留本机屏幕身份。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("恢复导入前的配置") { model.recoverImportBackup() }.appButton()
                    .disabled(!model.hasImportBackup || model.report.busy)
            }
            if let incoming = model.pendingImport {
                Section("待导入：\(incoming.profiles.count) 台设备") {
                    ForEach(incoming.profiles.prefix(5)) { profile in
                        LabeledContent(profile.name, value: profile.enabled ? profile.effectiveSpec.label : "自动调整已关闭")
                    }
                    if incoming.profiles.count > 5 { Text("以及其他 \(incoming.profiles.count - 5) 台设备。") }
                    HStack {
                        Button("合并到现有配置") { model.acceptImport(replace: false) }.appButton(prominent: true)
                        Button("替换全部配置", role: .destructive) { model.acceptImport(replace: true) }.appButton()
                        Button("取消") { model.pendingImport = nil }.appButton()
                    }.disabled(model.report.busy)
                }
            }
            if let notice = model.notice {
                Section { Label(notice, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange) }
            }
          }.formStyle(.grouped).tabItem { Label("配置备份", systemImage: "externaldrive") }
          UpdateView(model: model).tabItem { Label("更新", systemImage: "arrow.down.circle") }
        }.padding(16).frame(width: 680, height: 600)
    }
}
