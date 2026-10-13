import SwiftUI

struct SessionStatusView: View {
    var model: AppController
    var configure: () -> Void

    private var detail: String {
        switch model.sessionState {
        case .paused: "本次连接已暂停自动调整。"
        case .multiple: "保留一个连接后再自动匹配，包括同名设备。"
        case .permission: "允许 PadDisplay 读取 UU远程的连接设备名称，也可以先手动应用配置。"
        case .unconfigured: "请确认「\(model.controllers.first ?? "新设备")」的屏幕尺寸。"
        case .recoveryFailed, .failed: model.report.message
        case .companion: "请先退出 UU伴侣，再由 PadDisplay 调整屏幕。"
        case .disabled: "可手动应用屏幕配置，或重新打开自动匹配。"
        case .inactive: "此设备的配置已保存，连入时保持原桌面。"
        case .waiting: "设备连入后按已保存的配置匹配，断开后恢复原桌面。"
        default: model.connectionStatus
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if model.report.busy { ProgressView().controlSize(.small).frame(width: 28) }
            else {
                Image(systemName: model.sessionState.symbol)
                    .font(.system(size: 26)).foregroundStyle(model.sessionState.color).frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.report.busy ? model.report.message : model.sessionState.title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).accessibilityLabel(detail)
            }
            Spacer(minLength: 12)
            switch model.sessionState {
            case .permission:
                Button("打开系统设置") { model.openPermissions() }.appButton(prominent: true)
            case .unconfigured:
                Button("配置此设备", action: configure).appButton(prominent: true)
            case .paused, .disabled:
                Button("继续自动匹配") { model.resumeAutomatic() }.appButton(prominent: true)
            case .recoveryFailed:
                Button("重试恢复") { model.restore() }.appButton()
            case .waiting:
                Button("打开 UU远程") { model.openUU() }.appButton()
            default: EmptyView()
            }
        }
        .padding(16).groupedSurface()
        .accessibilityElement(children: .contain)
    }
}
