// 权限设置窗口：用 PermissionFlow 引导授权（打开系统设置隐私页 + 拖拽授权悬浮面板），状态实时刷新
import AppKit
import PermissionFlow
import ServiceManagement
import SwiftUI
import SystemSettingsKit

final class PermissionsModel: ObservableObject {
    @Published var axGranted = UUReader.isTrusted
    /// 由未全部授权变为全部授权时回调
    var onAllGranted: (() -> Void)?
    private var timer: Timer?

    // 看门狗改为在设置窗口「屏幕与兜底」中按需开启，这里只管辅助功能
    var allGranted: Bool { axGranted }
    static var allGranted: Bool { UUReader.isTrusted }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate() }

    func refresh() {
        let before = allGranted
        defer { if !before && allGranted { onAllGranted?() } }
        let ax = UUReader.isTrusted
        if ax != axGranted { axGranted = ax; Log.info("辅助功能权限：\(ax ? "已授权" : "未授权")") }
    }
}

private struct StatusBadge: View {
    let ok: Bool
    let okText: String
    let pendingText: String

    var body: some View {
        Label(ok ? okText : pendingText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(ok ? .green : .orange)
            .font(.callout.weight(.medium))
    }
}

private struct PermissionCard<Action: View>: View {
    let icon: String
    let title: Text
    let tag: String
    let detail: String
    let ok: Bool
    let okText: String
    let pendingText: String
    var tip: String?
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    title.font(.headline)
                    Text(tag).font(.caption).foregroundStyle(.secondary)
                }
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !ok, let tip {
                    Text(tip).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                StatusBadge(ok: ok, okText: okText, pendingText: pendingText)
                if !ok { action() }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel
    var onDone: () -> Void

    private var appURL: URL { Bundle.main.bundleURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("允许 UU远程伴侣 读取设备名称").font(.title2.bold())
                Text("这样平板或手机连上时，它才能认出是哪台设备，并换上合适的屏幕尺寸。")
                    .foregroundStyle(.secondary)
            }

            PermissionCard(
                icon: "hand.raised.fill",
                // macOS 27 起叫「设备控制和数据访问」，更早为「辅助功能」；固定取简体中文
                title: Text(PermissionFlowResources.localizedString(
                    for: PermissionFlowResources.accessibilityName(), localeIdentifier: "zh-Hans")),
                tag: "必需",
                detail: "用来读取 UU远程 里显示的设备名称，不会读取你的其他内容。",
                ok: model.axGranted,
                okText: "已授权",
                pendingText: "未授权",
                tip: "点「授权」会打开系统设置，旁边会出现一个小窗口，把里面的 UU远程伴侣 拖进列表就好。\n如果列表里已经有 UU远程伴侣 或 UUDisplay（旧名字），开关也开着，却还是显示未授权：先选中它，点「−」删掉，再拖一次。"
            ) {
                PermissionFlowButton(
                    pane: .accessibility,
                    suggestedAppURLs: [appURL],
                    configuration: .init(requiredAppURLs: [appURL], promptForAccessibilityTrust: false, localeIdentifier: "zh-Hans")
                ) { _ in
                    // 状态由左侧徽标统一显示，按钮只负责发起授权
                    Label("授权", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack {
                if model.allGranted {
                    Label("已经准备好了", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                Spacer()
                if model.allGranted {
                    Button("完成", action: onDone).keyboardShortcut(.defaultAction)
                } else {
                    Button("稍后再说", action: onDone)
                }
            }
        }
        .padding(22)
        .frame(width: 620)
    }
}

final class PermissionsWindowController {
    private var window: NSWindow?
    private var model: PermissionsModel?
    private var onDone: (() -> Void)?

    var isVisible: Bool { window != nil }

    /// - Parameter autoClose: 全部授权后自动关闭（首次启动引导时使用）
    func show(autoClose: Bool = false, onDone: (() -> Void)? = nil) {
        if let onDone { self.onDone = onDone }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = PermissionsModel()
        model.start()
        self.model = model
        let view = PermissionsView(model: model) { [weak self] in self?.close() }
        let hosting = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "权限设置"
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            self?.finish()
        }
        if autoClose {
            model.onAllGranted = { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.close() }
            }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }

    private func finish() {
        model?.stop()
        model = nil
        window = nil
        let done = onDone
        onDone = nil
        done?()
    }
}
