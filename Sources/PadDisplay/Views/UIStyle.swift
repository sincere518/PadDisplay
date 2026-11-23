import PadDisplayCore
import SwiftUI

extension View {
    @ViewBuilder func appButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }

    func groupedSurface() -> some View {
        background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

extension DeviceProfile {
    var displayTitle: String {
        name == "iPad Air (13 英寸, M2)" ? "iPad Air 13 英寸" : name.isEmpty ? "新设备" : name
    }

    var symbol: String {
        if ScreenPreset.isMacBookName(name) || ScreenPreset.macBooks.contains(where: { $0.id == presetID }) {
            return "laptopcomputer"
        }
        if name.lowercased().contains("iphone") { return "iphone" }
        if name.lowercased().contains("ipad") { return "ipad" }
        return "display"
    }

    var screenPreset: ScreenPreset? {
        if let presetID, let selected = ScreenPreset.all.first(where: { $0.id == presetID }) {
            return selected
        }
        func matchesSize(_ preset: ScreenPreset) -> Bool {
            (preset.spec.width == spec.width && preset.spec.height == spec.height) ||
            (preset.spec.width == spec.height && preset.spec.height == spec.width)
        }
        if let suggested = ScreenPreset.suggested(for: name), matchesSize(suggested) { return suggested }
        // 旧版手机和平板配置没有保存预设 ID，沿用按尺寸显示型号的行为。
        return ScreenPreset.all.first { preset in
            matchesSize(preset) && !ScreenPreset.macBooks.contains { $0.id == preset.id }
        }
    }

    var presetLabel: String { screenPreset?.label ?? "自定义尺寸" }
}

extension SessionState {
    var color: Color {
        switch self {
        case .ready, .manual, .paused: .green
        case .failed, .recoveryFailed: .red
        case .multiple, .companion: .orange
        default: .accentColor
        }
    }
}
