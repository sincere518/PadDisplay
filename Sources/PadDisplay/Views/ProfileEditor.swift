import PadDisplayCore
import SwiftUI

struct ProfileEditor: View {
    var model: AppController
    var onSave: (DeviceProfile) -> Bool
    private let original: DeviceProfile
    private let initialWidth: String
    private let initialHeight: String
    @State private var profile: DeviceProfile
    @State private var width: String
    @State private var height: String
    @State private var presetID: String
    @State private var portrait: Bool
    @State private var confirmRemoval = false
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field { case name, width, height }

    init(model: AppController, profile: DeviceProfile, onSave: @escaping (DeviceProfile) -> Bool) {
        self.model = model
        self.onSave = onSave
        original = profile
        initialWidth = profile.spec.width > 0 ? String(profile.spec.width) : ""
        initialHeight = profile.spec.height > 0 ? String(profile.spec.height) : ""
        _profile = State(initialValue: profile)
        _width = State(initialValue: initialWidth)
        _height = State(initialValue: initialHeight)
        _portrait = State(initialValue: profile.spec.width < profile.spec.height)
        _presetID = State(initialValue: ScreenPreset.all.first {
            ($0.spec.width == profile.spec.width && $0.spec.height == profile.spec.height) ||
            ($0.spec.width == profile.spec.height && $0.spec.height == profile.spec.width)
        }?.id ?? "custom")
    }

    private var candidate: DeviceProfile? {
        guard var value = profile.applyingSizeInput(width: width.trimmingCharacters(in: .whitespaces),
                                                    height: height.trimmingCharacters(in: .whitespaces)) else { return nil }
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var validation: String? {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "填写 UU远程中显示的完整设备名。" }
        if model.profiles.contains(where: { $0.id != profile.id && $0.name == name }) { return "此设备名称已经有配置。" }
        guard let candidate else { return "宽和高需要为整数像素。" }
        return candidate.enabled ? candidate.spec.validationError : nil
    }

    private var dirty: Bool { profile != original || width != initialWidth || height != initialHeight }
    private var existing: Bool { model.profiles.contains { $0.id == profile.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(existing ? "编辑设备配置" : "添加设备").font(.title2.weight(.semibold))
                Text(profile.displayTitle).font(.callout).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)
            Form {
                Section {
                    TextField("设备名称", text: $profile.name).focused($focus, equals: .name)
                    Text("与 UU远程中的名称保持一致；保存前不会改变当前屏幕。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("此设备连入时调整桌面", isOn: $profile.enabled)
                }
                if profile.enabled {
                    Section("屏幕") {
                        Picker("屏幕型号", selection: $presetID) {
                            Text("自定义 / 已保存尺寸").tag("custom")
                            ForEach(ScreenPreset.all) { Text($0.label).tag($0.id) }
                        }.onChange(of: presetID) { _, id in
                            if let spec = ScreenPreset.all.first(where: { $0.id == id })?.spec {
                                width = String(portrait ? spec.height : spec.width)
                                height = String(portrait ? spec.width : spec.height)
                            }
                        }
                        Picker("屏幕方向", selection: $portrait) {
                            Text("横屏").tag(false)
                            Text("竖屏").tag(true)
                        }.pickerStyle(.segmented).onChange(of: portrait) { _, isPortrait in
                            if let w = Int(width), let h = Int(height), (w < h) != isPortrait { swap(&width, &height) }
                        }
                        Text("按保存的方向应用，不跟随设备实时旋转。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("输出像素")
                            Spacer()
                            HStack {
                                TextField("宽", text: $width).labelsHidden()
                                    .accessibilityLabel("输出像素宽度").focused($focus, equals: .width)
                                Text("×").foregroundStyle(.secondary)
                                TextField("高", text: $height).labelsHidden()
                                    .accessibilityLabel("输出像素高度").focused($focus, equals: .height)
                            }.frame(width: 250).textFieldStyle(.roundedBorder)
                        }.accessibilityElement(children: .contain)
                        Toggle("高清文字（HiDPI）", isOn: $profile.spec.hiDPI)
                        if let candidate, candidate.spec.validationError == nil {
                            let desktopSize = "\(candidate.spec.width / (candidate.spec.hiDPI ? 2 : 1)) × \(candidate.spec.height / (candidate.spec.hiDPI ? 2 : 1))"
                            LabeledContent("桌面尺寸", value: desktopSize)
                                .foregroundStyle(.secondary)
                                .accessibilityElement(children: .ignore).accessibilityLabel("桌面尺寸").accessibilityValue(desktopSize)
                        }
                    }
                }
                if let validation {
                    Section { Label(validation, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange) }
                }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(profile.enabled ? "保存后，符合当前自动匹配策略时应用新配置。" : "保存后，此设备连入时保持原桌面。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if existing {
                        Button("移除设备…", role: .destructive) { confirmRemoval = true }.buttonStyle(.borderless)
                            .disabled(model.report.busy)
                    }
                    Spacer()
                    Button("取消", action: cancel).appButton().keyboardShortcut(.cancelAction)
                    Button("保存设置", action: save).appButton(prominent: true).keyboardShortcut(.defaultAction)
                        .disabled(validation != nil || model.report.busy)
                }
            }.padding(20)
        }
        .frame(width: 580, height: profile.enabled ? 620 : 400)
        .interactiveDismissDisabled(dirty)
        .onAppear { if !existing { focus = .name } }
        .onSubmit(save)
        .confirmationDialog("移除此设备配置？", isPresented: $confirmRemoval) {
            Button("移除", role: .destructive) { model.remove(profile.id); dismiss() }
        } message: { Text("再次连入时，需要重新配置此设备。") }
        .alert("保存对设备配置的更改？", isPresented: $confirmDiscard) {
            Button("保存", action: save).disabled(validation != nil || model.report.busy)
            Button("放弃更改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        } message: { Text("未保存的更改不会应用到当前屏幕。") }
    }

    private func cancel() {
        if dirty { confirmDiscard = true }
        else { dismiss() }
    }

    private func save() {
        guard validation == nil, let candidate else {
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                model.profiles.contains(where: { $0.id != profile.id && $0.name == profile.name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                focus = .name
            } else { focus = Int(width) == nil ? .width : .height }
            return
        }
        if onSave(candidate) { dismiss() }
    }
}
