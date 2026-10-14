import SwiftUI

struct UpdateView: View {
    var model: AppController
    @State private var confirmingInstall = false

    var body: some View {
        @Bindable var updates = model.updates
        Form {
            Section("应用更新") {
                LabeledContent("当前版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "源码构建")
                TextField("更新源", text: $updates.source).disabled(updates.busy)
                Text("支持 GitHub 仓库地址或 HTTPS 更新描述文件。默认使用作者的 PadDisplay 仓库。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("每天自动检查一次", isOn: $updates.automaticChecks).onChange(of: updates.automaticChecks) { _, enabled in
                    if enabled { updates.checkIfScheduled() }
                }
                HStack {
                    Button("检查更新") { updates.check() }.appButton(prominent: true).disabled(updates.busy)
                    Button("查看发布页") { updates.openReleases() }.appButton()
                    if updates.busy { ProgressView().controlSize(.small).accessibilityHidden(true) }
                }
                Text(updates.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let release = updates.release {
                Section("新版本 \(release.version)") {
                    Text(release.notes).font(.callout).textSelection(.enabled)
                    if updates.candidate != nil {
                        Button("安装并重新打开…") { confirmingInstall = true }.appButton(prominent: true)
                            .disabled(updates.busy || model.report.busy)
                    } else {
                        Button("下载并校验") { updates.download() }.appButton(prominent: true).disabled(updates.busy)
                    }
                }
            }
            Section {
                Text("更新沿用当前签名身份，先校验 SHA-256 和应用签名，再恢复桌面后安装。源码自行构建使用不同身份时，请核实发布页并手动安装。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .alert("安装新版本并重新打开 PadDisplay？", isPresented: $confirmingInstall) {
            Button("安装更新") { updates.install(model: model) }
            Button("取消", role: .cancel) {}
        } message: { Text("会先结束当前远程屏幕并恢复原桌面，随后替换应用。设备配置会保留。") }
    }
}
