import SwiftUI

struct ConnectionAssistantView: View {
    var model: AppController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("让远程屏幕准备就绪").font(.title2.weight(.semibold))
                Text("完成下面几步，即可为不同设备匹配各自的桌面。")
                    .font(.callout).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    step("1", "允许识别连接设备", detail: model.permissionGranted ? "辅助功能权限已开启。" : "在系统隐私设置中允许 PadDisplay。", done: model.permissionGranted)
                    Button("打开权限设置") { model.openPermissions() }.appButton(prominent: !model.permissionGranted)
                    Divider()
                    step("2", "打开 UU远程并连接", detail: model.connectionStatus, done: !model.controllers.isEmpty)
                    Button("打开 UU远程") { model.openUU() }.appButton()
                    Divider()
                    step("3", "保存设备的屏幕配置", detail: "在主窗口选择设备，确认尺寸、方向与显示预设。", done: model.currentProfile?.enabled == true && model.currentProfile?.validationError == nil)
                    Divider()
                    step("4", "确认远程屏幕已就绪", detail: "出现「屏幕已就绪」后，在 iPad／iPhone 的 UU显示器列表中选择该屏幕。", done: model.report.active != nil && !model.report.busy)
                }.padding(18).groupedSurface()
                DiagnosticsView(model: model)
                HStack {
                    Spacer()
                    Button("完成引导") { model.completeSetup(); dismiss() }.appButton(prominent: true)
                }
            }.padding(24)
        }.frame(width: 620, height: 720).onAppear { model.checkHealth() }
    }

    private func step(_ number: String, _ title: String, detail: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.1)).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").foregroundStyle(.green) }
                else { Text(number).foregroundStyle(Color.accentColor) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DiagnosticsView: View {
    var model: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("连接健康检查").font(.headline)
                Spacer()
                if model.checkingHealth { ProgressView().controlSize(.small).accessibilityHidden(true) }
                Button("检查") { model.checkHealth() }.appButton().disabled(model.checkingHealth)
            }
            if let health = model.health {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(health.checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.status == "ok" ? "checkmark.circle.fill" : check.status == "info" ? "info.circle" : "exclamationmark.circle.fill")
                                .foregroundStyle(check.status == "ok" ? Color.green : check.status == "info" ? Color.secondary : Color.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(check.title).font(.callout.weight(.medium))
                                Text(check.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).groupedSurface()
                HStack {
                    Text(health.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("导出诊断…") { model.exportHealth() }.appButton()
                    if model.report.recoveryNeeded { Button("重试恢复") { model.restore() }.appButton().disabled(model.report.busy) }
                }
                Text("导出包含版本、检查结果和显示器尺寸，不含 UU设备码、账号、窗口标题或截图。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
