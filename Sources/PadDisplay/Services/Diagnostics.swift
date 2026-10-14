import CoreGraphics
import Foundation
import AppKit
import PadDisplayCore

struct HealthItem: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: String
}

struct HealthReport: Codable {
    let date: Date
    let version: String
    let system: String
    let checks: [HealthItem]
    let screens: [ScreenDiagnostic]
}

struct ScreenDiagnostic: Codable {
    let id: UInt32
    let main: Bool
    let vendor: UInt32
    let serial: UInt32
    let pixelWidth: Int
    let pixelHeight: Int
    let logicalWidth: Int
    let logicalHeight: Int
    let refreshRate: Double
    let x: Int
    let y: Int
}

enum Diagnostics {
    @MainActor static func check(model: AppController, reading: ConnectionReading) -> HealthReport {
        var checks: [HealthItem] = []
        func add(_ id: String, _ title: String, _ detail: String, _ status: String) {
            checks.append(.init(id: id, title: title, detail: detail, status: status))
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.netease.uuremote").isEmpty
        add("permission", "识别权限", model.permissionGranted ? "已允许读取连接设备。" : "请在系统隐私设置中允许 PadDisplay。", model.permissionGranted ? "ok" : "error")
        add("remote", "UU远程", running ? "Mac 端已运行。" : "请打开 Mac 端 UU远程。", running ? "ok" : "warning")
        add("reading", "连接表格", reading.detail, reading.controllers == nil ? "warning" : "ok")
        if let count = reading.controllerCount ?? reading.controllers?.count {
            add("count", "连接数量", count > 1 ? "当前有 \(count) 台设备；保留一个连接后才能自动匹配。" : count == 0 ? "尚无远程设备连接，可以先检查保存的配置。" : "当前只有一台设备连接。", count > 1 ? "warning" : count == 0 ? "info" : "ok")
        } else { add("count", "连接数量", "当前无法确认连接数量，请先恢复连接表格读取。", "warning") }
        for (index, name) in (reading.controllers ?? []).enumerated() {
            let profile = model.profiles.first { $0.name == name }
            add("profile-\(index)", "当前设备配置", profile.map { $0.enabled ? ($0.validationError ?? "尺寸、方向与屏幕身份均有效。") : "此设备关闭了自动调整。" } ?? "请添加与连接设备同名的配置。",
                profile?.enabled == true && profile?.validationError == nil ? "ok" : "warning")
        }
        let screens = screenRecords()
        if model.report.busy {
            add("screen", "虚拟屏幕", model.report.message + " 完成后请再检查。", "info")
        } else if let active = model.report.active {
            let screen = screens.first { $0.vendor == 0x5044 && $0.serial == active.serial }
            let matches = screen?.pixelWidth == active.spec.width && screen?.pixelHeight == active.spec.height &&
                screen?.logicalWidth == active.spec.width / (active.spec.hiDPI ? 2 : 1) &&
                screen?.logicalHeight == active.spec.height / (active.spec.hiDPI ? 2 : 1) &&
                screen?.main == (active.role == .main)
            add("screen", "虚拟屏幕", matches ? "输出为 \(active.spec.label)，\(active.role.label)。请在 UU客户端选择此屏幕。" : "实际屏幕与请求不一致，请恢复后重新应用。", matches ? "ok" : "error")
        } else {
            add("screen", "虚拟屏幕", model.report.failed ? model.report.message : "尚未应用；连接设备或手动应用后再检查。", model.report.failed ? "error" : "info")
        }
        add("recovery", "桌面恢复", model.report.recoveryNeeded ? model.report.message : model.report.warning ?? "当前无待处理的恢复错误。", model.report.recoveryNeeded ? "error" : model.report.warning == nil ? "ok" : "warning")
        return HealthReport(date: Date(), version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "源码构建",
                            system: ProcessInfo.processInfo.operatingSystemVersionString, checks: checks, screens: screens)
    }

    static func screenRecords() -> [ScreenDiagnostic] {
        VirtualDisplayService.displays().sorted().map { id in
            let mode = CGDisplayCopyDisplayMode(id), origin = CGDisplayBounds(id).origin
            return ScreenDiagnostic(id: id, main: CGDisplayIsMain(id) != 0, vendor: CGDisplayVendorNumber(id),
                                    serial: CGDisplaySerialNumber(id), pixelWidth: mode?.pixelWidth ?? 0,
                                    pixelHeight: mode?.pixelHeight ?? 0, logicalWidth: mode?.width ?? 0,
                                    logicalHeight: mode?.height ?? 0, refreshRate: mode?.refreshRate ?? 0,
                                    x: Int(origin.x), y: Int(origin.y))
        }
    }
    static func screens() -> [[String: Any]] {
        VirtualDisplayService.displays().sorted().map { id in
            let mode = CGDisplayCopyDisplayMode(id)
            let origin = CGDisplayBounds(id).origin
            return ["id": id, "main": CGDisplayIsMain(id) != 0, "vendor": CGDisplayVendorNumber(id),
                    "pixelWidth": mode?.pixelWidth ?? 0, "pixelHeight": mode?.pixelHeight ?? 0,
                    "logicalWidth": mode?.width ?? 0, "logicalHeight": mode?.height ?? 0,
                    "x": Int(origin.x), "y": Int(origin.y)]
        }
    }

    static func write(_ value: [String: Any], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { FileHandle.standardError.write(Data("无法写入诊断结果：\(error)\n".utf8)) }
    }
}
