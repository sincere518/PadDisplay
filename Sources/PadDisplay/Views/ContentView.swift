import PadDisplayCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppController
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("设备") {
                    ForEach(model.profiles) { profile in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name.isEmpty ? "新设备" : profile.name).lineLimit(1)
                                Text(profile.enabled ? profile.spec.label : "不调整").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: profile.enabled ? "ipad.landscape" : "desktopcomputer")
                        }.tag(profile.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 300)
            .safeAreaInset(edge: .bottom) {
                Button { selection = model.addDevice() } label: {
                    Label("添加设备", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderless).padding()
            }
        } detail: {
            VStack(spacing: 0) {
                status.padding(20)
                Divider()
                if let profile = model.profiles.first(where: { $0.id == selection }) {
                    ProfileEditor(model: model, profile: profile).id(profile.id)
                } else {
                    ContentUnavailableView("为每台设备准备合适的桌面", systemImage: "display.2",
                                           description: Text("添加设备并保存屏幕尺寸，之后连入时自动应用。"))
                }
            }
        }
        .navigationTitle("PadDisplay · 远程桌面助手")
        .frame(minWidth: 780, minHeight: 640)
        .onAppear { if selection == nil { selection = model.profiles.first?.id } }
        .toolbar {
            Button("恢复原桌面", systemImage: "arrow.uturn.backward") { model.restore() }
                .disabled(model.report.busy)
        }
        .alert("PadDisplay", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("好") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.report.active == nil ? "display.2" : "checkmark.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(model.report.failed ? Color.red : Color.accentColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.report.message).font(.headline)
                    Text(model.connectionStatus).font(.subheadline).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if !model.controllers.isEmpty {
                        Text(model.controllers.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.report.busy { ProgressView().controlSize(.small) }
            }
            HStack {
                Toggle("自动匹配设备", isOn: $model.automatic).toggleStyle(.switch)
                Spacer()
                Button("打开 UU远程") { model.openUU() }
            }
            if !model.permissionGranted {
                HStack {
                    Text("首次使用需要允许 PadDisplay 读取 UU远程的连接设备名称。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("授权识别连接") { model.openPermissions() }
                }
            }
        }
    }
}
