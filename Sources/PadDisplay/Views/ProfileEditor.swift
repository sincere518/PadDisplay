import PadDisplayCore
import SwiftUI

struct ProfileEditor: View {
    var model: AppController
    @State var profile: DeviceProfile
    @State private var width: String
    @State private var height: String
    @State private var presetID = "custom"
    @State private var confirmRemoval = false

    init(model: AppController, profile: DeviceProfile) {
        self.model = model
        _profile = State(initialValue: profile)
        _width = State(initialValue: String(profile.spec.width))
        _height = State(initialValue: String(profile.spec.height))
    }

    private var candidate: DeviceProfile? {
        guard let w = Int(width), let h = Int(height) else { return nil }
        var value = profile
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.spec.width = w
        value.spec.height = h
        return value
    }

    private var validation: String? {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "填写 UU远程中显示的完整设备名。" }
        if model.profiles.contains(where: { $0.id != profile.id && $0.name == profile.name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            return "此设备名称已经有配置。"
        }
        guard let candidate else { return "宽和高需要为整数像素。" }
        return candidate.enabled ? candidate.spec.validationError : nil
    }

    var body: some View {
        Form {
            Section("连接设备") {
                TextField("设备名称", text: $profile.name)
                Text("与 UU远程中的名称保持一致；不同设备各自保存设置。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("此设备连入时调整桌面", isOn: $profile.enabled)
            }
            if profile.enabled {
                Section("远程屏幕") {
                    Picker("屏幕型号", selection: $presetID) {
                        Text("自定义 / 已保存尺寸").tag("custom")
                        ForEach(ScreenPreset.all) { preset in Text(preset.label).tag(preset.id) }
                    }.onChange(of: presetID) { _, id in
                        if let spec = ScreenPreset.all.first(where: { $0.id == id })?.spec {
                            width = String(spec.width)
                            height = String(spec.height)
                        }
                    }
                    HStack {
                        TextField("宽", text: $width).frame(maxWidth: 150)
                        Text("×").foregroundStyle(.secondary)
                        TextField("高", text: $height).frame(maxWidth: 150)
                        Text("像素").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text((Int(width) ?? 0) >= (Int(height) ?? 0) ? "当前：横屏" : "当前：竖屏")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("交换宽高") { swap(&width, &height) }
                    }
                    Toggle("高清文字（HiDPI）", isOn: $profile.spec.hiDPI)
                    Text("按设备的原生像素填写。高清模式保持像素清晰，同时让文字和按钮大小适合操作。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                if let validation { Text(validation).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("保存设备设置") { if let candidate { model.save(candidate) } }
                        .buttonStyle(.borderedProminent).disabled(validation != nil)
                    Button("立即使用这个屏幕") { if let candidate { model.useManually(candidate) } }
                        .disabled(validation != nil || !profile.enabled || model.report.busy || model.companionRunning)
                }
                Text("屏幕就绪后，在 iPad 的 UU远程显示器列表中选择「PadDisplay」。若 UU 仍显示原来的屏幕，需要在连接端切换一次。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("移除此设备配置", role: .destructive) { confirmRemoval = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("移除此设备配置？", isPresented: $confirmRemoval) {
            Button("移除", role: .destructive) { model.remove(profile.id) }
        } message: { Text("再次连入时，可重新添加并设置屏幕尺寸。") }
    }
}
