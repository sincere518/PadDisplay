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
        if name.lowercased().contains("iphone") { return "iphone" }
        if name.lowercased().contains("ipad") { return "ipad" }
        return "display"
    }

    var presetLabel: String {
        ScreenPreset.all.first {
            ($0.spec.width == spec.width && $0.spec.height == spec.height) ||
            ($0.spec.width == spec.height && $0.spec.height == spec.width)
        }?.label ?? "自定义尺寸"
    }
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
