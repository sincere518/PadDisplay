import PadDisplayCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppController
    @Environment(\.openWindow) private var openWindow
    @State private var selection: UUID?
    @State private var editing: DeviceProfile?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("设备") {
                    ForEach(model.profiles) { profile in
                        HStack(spacing: 12) {
                            Image(systemName: profile.symbol).font(.system(size: 22, weight: .regular)).frame(width: 26)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(profile.displayTitle).font(.callout.weight(.medium)).lineLimit(1)
                                HStack(spacing: 5) {
                                    if model.controllers.contains(profile.name) {
                                        Circle().fill(.green).frame(width: 6, height: 6)
                                    }
                                    Text(model.controllers.contains(profile.name) ? "已连接" : "未连接")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical, 8).tag(profile.id).help(profile.name)
                        .contextMenu {
                            Button("编辑配置…") { editing = profile }
                            Button(profile.favorite ? "取消收藏" : "收藏到菜单栏") { model.setFavorite(profile, !profile.favorite) }
                            Button("复制快捷指令链接") { model.copyShortcutURL(for: profile) }
                        }
                    }
                }
            }.listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 208, ideal: 228, max: 290)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Button { editing = model.makeDraft() } label: {
                        Label("添加设备", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    SettingsLink { Label("设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading) }
                    Button { openWindow(id: "connection") } label: {
                        Label("连接助手", systemImage: "checkmark.shield").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { openWindow(id: "about") } label: {
                        Label("关于 PadDisplay", systemImage: "info.circle").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.borderless).font(.callout).padding(16)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if model.sessionState != .ready && model.sessionState != .manual {
                        SessionStatusView(model: model) { editing = model.makeDraft() }
                    }
                    if let notice = model.notice {
                        HStack(alignment: .top) {
                            Label(notice, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                            Spacer()
                            Button("关闭提示", systemImage: "xmark") { model.notice = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        }.font(.callout).padding(12).groupedSurface()
                    }
                    if let profile = model.profiles.first(where: { $0.id == selection }) {
                        DeviceDetailView(model: model, profile: profile) { editing = $0 }
                    } else {
                        ContentUnavailableView {
                            Label("为每台设备准备合适的桌面", systemImage: "display.2")
                        } description: {
                            Text("添加设备并保存屏幕尺寸，之后连入时自动应用。")
                        } actions: {
                            Button("添加设备") { editing = model.makeDraft() }.appButton(prominent: true)
                        }
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("PadDisplay")
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Text("自动匹配").font(.callout)
                    Toggle("自动匹配设备", isOn: $model.automatic).labelsHidden()
                        .accessibilityLabel("自动匹配设备").toggleStyle(.switch).controlSize(.small)
                        .help("按当前单个连接设备的配置自动调整屏幕。")
                }
            }
            if #available(macOS 26, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
            ToolbarItem(placement: .primaryAction) {
                Button("恢复原桌面", systemImage: "arrow.uturn.backward") { model.restore() }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.report.busy)
            }
        }
        .onAppear { selectActiveOrFirst(); if model.needsSetup { openWindow(id: "connection") } }
        .onChange(of: model.report.active) { _, request in
            if editing == nil, let request, let profile = model.profiles.first(where: { $0.name == request.name }) {
                selection = profile.id
            }
        }
        .onChange(of: model.profiles) { _, profiles in
            if !profiles.contains(where: { $0.id == selection }) { selectActiveOrFirst() }
        }
        .sheet(item: $editing) { profile in
            ProfileEditor(model: model, profile: profile) { saved in
                guard model.save(saved) else { return false }
                selection = saved.id
                return true
            }
        }
    }

    private func selectActiveOrFirst() {
        if selection == nil || !model.profiles.contains(where: { $0.id == selection }) {
            selection = model.profiles.first(where: { $0.name == model.report.active?.name })?.id ?? model.profiles.first?.id
        }
    }
}
