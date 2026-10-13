import Foundation

enum SessionState: Equatable {
    case waiting, permission, working, ready, manual, paused, multiple, unconfigured, inactive, disabled, failed, recoveryFailed, companion

    var title: String {
        switch self {
        case .waiting: "等待远程设备连接"
        case .permission: "允许识别连接设备"
        case .working: "正在调整屏幕…"
        case .ready: "屏幕已就绪"
        case .manual: "手动屏幕已就绪"
        case .paused: "已恢复原桌面"
        case .multiple: "多个设备同时连接"
        case .unconfigured: "此设备还没有屏幕配置"
        case .inactive: "此设备不调整桌面"
        case .disabled: "自动匹配已关闭"
        case .failed: "显示调整未完成"
        case .recoveryFailed: "原桌面尚未恢复"
        case .companion: "UU伴侣正在调整显示器"
        }
    }

    var symbol: String {
        switch self {
        case .ready, .manual, .paused: "checkmark.circle.fill"
        case .failed, .recoveryFailed: "exclamationmark.triangle.fill"
        case .multiple, .companion: "display.2"
        case .permission: "lock.shield"
        case .unconfigured: "plus.rectangle.on.rectangle"
        default: "display"
        }
    }
}
