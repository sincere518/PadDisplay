// 设备配置面板（设置窗口第一栏）：读取 UU 设备列表，确认类型与分辨率
import AppKit
import SwiftUI

final class WizardModel: ObservableObject {
    @Published var rows: [DeviceConfig] = []
    @Published var defaultDevice: String = ""
    @Published var message: String?
    @Published var trusted = UUReader.isTrusted
    @Published var newName = ""

    private let store = ConfigStore.shared

    init() { load() }

    func load() {
        trusted = UUReader.isTrusted
        guard trusted else {
            message = "需要先完成授权，才能读到 UU远程 里的设备。授权后点「重新读取」。"
            rows = store.config.devices
            defaultDevice = store.config.defaultDevice ?? ""
            return
        }
        if !UUReader.hasMainWindow { UUReader.showMainWindow(); Thread.sleep(forTimeInterval: 1) }
        let found = (UUReader.readDevices() ?? []).filter { !$0.isSelf }
        // 已有配置保留，新设备按名称预填
        var merged: [DeviceConfig] = found.map { d in
            store.device(named: d.name) ?? DeviceConfig.make(name: d.name, kind: Presets.guessKind(name: d.name, isComputerGroup: d.isComputerGroup))
        }
        for old in store.config.devices where !merged.contains(where: { $0.name == old.name }) { merged.append(old) }
        rows = merged
        message = found.isEmpty
            ? "没有读到设备。请打开 UU远程，停在「全部设备」页面，再点「重新读取」；也可以在下方手动添加。"
            : "在 UU远程 里找到 \(found.count) 台设备（不含这台 Mac）。请确认每台设备的类型，以及要用的屏幕尺寸。"
        defaultDevice = store.config.defaultDevice ?? rows.first { $0.kind == .tablet }?.name ?? ""
    }

    func addManual() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !rows.contains(where: { $0.name == n }) else { return }
        rows.append(DeviceConfig.make(name: n, kind: Presets.guessKind(name: n, isComputerGroup: false)))
        newName = ""
    }

    func save() {
        store.config.devices = rows
        store.config.defaultDevice = defaultDevice.isEmpty ? nil : defaultDevice
    }
}

struct DeviceRow: View {
    @Binding var cfg: DeviceConfig
    var onDelete: () -> Void

    private var presetBinding: Binding<String> {
        Binding(get: { cfg.presetID ?? Presets.customID }, set: { id in
            cfg.presetID = id == Presets.customID ? nil : id
            if let p = Presets.preset(id: id) { cfg.width = p.width; cfg.height = p.height }
        })
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(cfg.name).frame(width: 150, alignment: .leading).lineLimit(1)
            Picker("", selection: Binding(get: { cfg.kind }, set: { k in
                cfg.kind = k
                if k != .computer, Presets.preset(id: cfg.presetID)?.kind != k {
                    let fresh = DeviceConfig.make(name: cfg.name, kind: k)
                    cfg.presetID = fresh.presetID; cfg.width = fresh.width; cfg.height = fresh.height
                }
            })) {
                ForEach(DeviceKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)

            if cfg.kind == .computer {
                Text("保持原样").foregroundStyle(.secondary)
                Spacer()
            } else {
                Picker("", selection: presetBinding) {
                    ForEach(Presets.all.filter { $0.kind == cfg.kind }) { Text($0.label).tag($0.id) }
                    Text("自定义").tag(Presets.customID)
                }
                .labelsHidden().frame(width: 230)
                if cfg.presetID == nil {
                    TextField("宽", value: $cfg.width, format: .number.grouping(.never)).frame(width: 60)
                    Text("×")
                    TextField("高", value: $cfg.height, format: .number.grouping(.never)).frame(width: 60)
                }
                Toggle("高清", isOn: $cfg.hiDPI)
                Spacer()
            }
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("从列表中移除")
        }
    }
}

struct WizardView: View {
    @ObservedObject var model: WizardModel
    var openPermissions: (() -> Void)?
    /// 嵌入设置窗口时使用面板标题与自适应宽度
    var embedded = false
    var savedHint = false
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(embedded ? "设置平板和手机" : "UU远程伴侣 · 设置平板和手机").font(.title2.bold())
            if let m = model.message { Text(m).foregroundStyle(.secondary) }
            if !model.trusted {
                HStack {
                    Button("去授权…") { openPermissions?() }
                    Text("授权后点「重新读取」").foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach($model.rows) { $row in
                        DeviceRow(cfg: $row) { model.rows.removeAll { $0.name == row.name } }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                TextField("手动添加设备（名字要和 UU远程 里显示的一样）", text: $model.newName).frame(width: 260)
                Button("添加", action: model.addManual)
                Spacer()
            }
            Divider()
            HStack {
                Picker("认不出设备时，默认当作", selection: $model.defaultDevice) {
                    Text("不调整").tag("")
                    ForEach(model.rows.filter { $0.kind != .computer }) { Text($0.name).tag($0.name) }
                }
                .frame(width: 380)
                Spacer()
                if savedHint { Label("已保存", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Button("重新读取") { model.load() }
                Button("保存") { model.save(); onSave() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(embedded ? 24 : 20)
        .frame(minWidth: embedded ? nil : 860, minHeight: 460)
    }
}
