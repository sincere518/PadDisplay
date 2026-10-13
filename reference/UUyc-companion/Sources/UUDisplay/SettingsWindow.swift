// 设置窗口（上中下结构）
// 上：工作原理图「控制端 ⇢ 被控 Mac ⇢ 兜底」，点各自按钮向下展开对应面板（同一时间只展开一个）
// 中：立即恢复所有屏幕 / 权限设置 / 功能导览
// 下：关于本应用 / 完全退出（右对齐）
import AppKit
import ServiceManagement
import SwiftUI
import SystemSettingsKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case controller, controlled, fallback
    var id: String { rawValue }
}

final class SettingsModel: ObservableObject {
    // 注意：SwiftUI 的 @State 在仅有 Command Line Tools 时无法编译（宏插件缺失），界面状态统一放在 ObservableObject 里
    @Published var expanded: SettingsPane?
    @Published var autoVirtual: Bool
    @Published var disablePhysical: Bool
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var watchdogEnabled: Bool
    @Published var watchdogRunning = Watchdog.isRunning
    @Published var physicalOff = PhysicalDisplays.pending != nil
    @Published var savedHint = false

    let devices = WizardModel()
    var onConfigChanged: (() -> Void)?
    var setDisablePhysical: ((Bool) -> Void)?
    var setPaused: ((Bool) -> Void)?
    var restorePhysical: (() -> Void)?
    var openPermissions: (() -> Void)?
    var openTour: (() -> Void)?
    private var timer: Timer?
    private let store = ConfigStore.shared

    init() {
        autoVirtual = !store.config.paused
        disablePhysical = store.config.shouldDisablePhysical
        watchdogEnabled = store.config.shouldRunWatchdog
    }

    var fallbackAvailable: Bool { autoVirtual && disablePhysical }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() { timer?.invalidate() }

    func refresh() {
        let running = Watchdog.isRunning
        if running != watchdogRunning { watchdogRunning = running }
        let off = PhysicalDisplays.pending != nil
        if off != physicalOff { physicalOff = off }
        let login = SMAppService.mainApp.status == .enabled
        if login != launchAtLogin { launchAtLogin = login }
    }

    /// 点同一个按钮再次收起；兜底面板只在开启软关闭后可展开
    func toggle(_ pane: SettingsPane) {
        if pane == .fallback && !fallbackAvailable { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            expanded = expanded == pane ? nil : pane
        }
    }

    func saveDevices() {
        devices.save()
        onConfigChanged?()
        savedHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.savedHint = false }
    }

    func toggleLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "开机自动打开没有设置成功：\(error.localizedDescription)。请先把 UU远程伴侣 放进「应用程序」文件夹，再试一次。"
            Log.info("⚠️ 开机启动设置失败：\(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func toggleAutoVirtual(_ on: Bool) {
        autoVirtual = on
        setPaused?(!on)
        Log.info("设置：自动启动虚拟屏 → \(on ? "开" : "关")")
        if !fallbackAvailable && expanded == .fallback { withAnimation { expanded = nil } }
    }

    func toggleDisablePhysical(_ on: Bool) {
        disablePhysical = on
        setDisablePhysical?(on)
        Log.info("设置：自动软关闭物理屏 → \(on ? "开" : "关")")
        if !on && expanded == .fallback { withAnimation { expanded = nil } }
    }

    /// 只有在这里开启，看门狗才会安装为 LaunchAgent 并加载；关闭即卸载
    func toggleWatchdog(_ on: Bool) {
        watchdogEnabled = on
        store.config.watchdogEnabled = on
        Log.info("设置：看门狗 → \(on ? "开" : "关")")
        if on { WatchdogAgent.ensureInstalled() } else { WatchdogAgent.uninstall() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
    }

    func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        let credits = NSAttributedString(
            string: "用平板或手机通过 UU远程 操控这台 Mac 时，它会自动准备一块和你的设备尺寸一致的屏幕，让画面刚好铺满；断开后一切恢复原样。\n\n使用的开源组件：PermissionFlow、TourKit、FreeDisplay（均为 MIT 协议）",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "UU远程伴侣",
            .applicationVersion: version,
            .credits: credits,
        ])
    }

    /// 完全退出：停掉本次登录中的看门狗（不卸载，下次打开 App 或重新登录时恢复），再退出主程序
    func quitCompletely() {
        Log.info("完全退出：停止看门狗并退出主程序")
        WatchdogAgent.stopForSession()
        NSApp.terminate(nil)
    }
}

// MARK: - 快捷键示意图（⌃ ⌥ ⌘ 9 四个键）

private struct HotkeyCap: View {
    let symbol: String
    var name: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor)
            .shadow(color: .black.opacity(0.18), radius: 1, y: 2)
            .overlay(
                VStack(spacing: 2) {
                    Text(symbol).font(.system(size: name == nil ? 28 : 24, weight: .semibold))
                    if let name { Text(name).font(.system(size: 11, weight: .medium)) }
                }
                .foregroundStyle(.white)
            )
            .frame(width: name == nil ? 64 : 78, height: 64)
    }
}

struct HotkeyKeysView: View {
    var body: some View {
        HStack(spacing: 10) {
            HotkeyCap(symbol: "⌃", name: "control")
            plus
            HotkeyCap(symbol: "⌥", name: "option")
            plus
            HotkeyCap(symbol: "⌘", name: "command")
            plus
            HotkeyCap(symbol: "9")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("快捷键：同时按下 control、option、command 和 9")
    }

    private var plus: some View {
        Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(.secondary)
    }
}

// MARK: - 面板

private struct Card<Content: View>: View {
    let icon: String
    let title: String
    let tag: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 24)
                Text(title).font(.headline)
                Text(tag).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - 工作原理图

/// 虚线箭头，中间带说明文字；纵向对齐到图标中线
private struct DashedConnector: View {
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 5))
                        p.addLine(to: CGPoint(x: w - 8, y: 5))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
                    Path { p in
                        p.move(to: CGPoint(x: w - 10, y: 0))
                        p.addLine(to: CGPoint(x: w, y: 5))
                        p.addLine(to: CGPoint(x: w - 10, y: 10))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 10)
        }
        .padding(.top, 44)  // 文字 + 线大约落在 128 图标的垂直中部
        .frame(minWidth: 70, maxWidth: .infinity)
    }
}

/// 控制端图标：平板 + 手机 组合
private struct ControllerIcon: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "ipad.landscape")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 112)
                .offset(x: -8, y: -14)
            Image(systemName: "iphone")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(height: 64)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        }
        .frame(width: 128, height: 128)
    }
}

private struct FlowNode<Icon: View>: View {
    let caption: String
    let buttonTitle: String
    var enabled = true
    var selected = false
    var hint: String? = nil
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: 10) {
            icon()
                .font(.system(size: 96, weight: .light))
                .foregroundStyle(enabled ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: 128, height: 128)
            Text(caption).font(.subheadline.weight(.medium)).foregroundStyle(enabled ? .primary : .secondary)
            Group {
                if selected {
                    Button(action: action) { Label(buttonTitle, systemImage: "chevron.up") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(action: action) { Label(buttonTitle, systemImage: "chevron.down") }
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            .disabled(!enabled)
            .help(hint ?? "")
        }
        .frame(width: 180)
    }
}

// MARK: - 展开面板

/// 被控制端：开机启动 / 自动启动虚拟屏 / 自动软关闭物理屏
struct ControlledPanel: View {
    @ObservedObject var model: SettingsModel

    private func row(_ title: String, _ detail: String, isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(enabled ? .primary : .secondary)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().disabled(!enabled)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置这台 Mac").font(.title3.bold())
            row("开机时自动打开",
                "开机后它会安静地待在菜单栏里，平板或手机随时连上都能用。",
                isOn: Binding(get: { model.launchAtLogin }, set: { model.toggleLaunchAtLogin($0) }))
            if let err = model.loginError {
                Text(err).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            row("自动准备虚拟屏幕",
                "平板或手机连上这台 Mac 时，自动准备一块和它尺寸一致的屏幕，远程画面刚好铺满、文字清晰；断开后自动收起。关掉后，连上时不做任何调整。",
                isOn: Binding(get: { model.autoVirtual }, set: { model.toggleAutoVirtual($0) }))
            Divider()
            row("远程时熄灭 Mac 的屏幕",
                "远程期间，Mac 自带的屏幕和外接显示器会暂时熄灭，只留下那块虚拟屏幕，打开的窗口不会跑到你看不见的地方。断开后屏幕会自动亮回来。用电脑连接时不受影响。万一屏幕没有亮回来，可以看看「找回屏幕的方法」。",
                isOn: Binding(get: { model.disablePhysical }, set: { model.toggleDisablePhysical($0) }),
                enabled: model.autoVirtual)
            if !model.autoVirtual {
                Text("要先打开「自动准备虚拟屏幕」。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 兜底选项：快捷键 + 看门狗
struct FallbackPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("找回屏幕的方法").font(.title3.bold())
                Text("远程结束后，屏幕一般会自动亮回来。万一没有，用下面的方法就能找回。").foregroundStyle(.secondary)
            }

            Card(icon: "keyboard", title: "快捷键", tag: "随时可用") {
                Text("坐在 Mac 前、屏幕黑着的时候，同时按下 **⌃ control + ⌥ option + ⌘ command + 9**，所有屏幕会立刻亮起来。远程画面不受影响，这次连接期间也不会再熄灭屏幕。")
                    .fixedSize(horizontal: false, vertical: true)
                HotkeyKeysView()
                Text("点设置窗口或菜单栏里的「立即恢复所有屏幕」，效果一样。")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Card(icon: "shield.lefthalf.filled", title: "后台守护", tag: "可选") {
                Text("打开后，会有一个小助手在后台值守，每 5 秒看一眼。遇到下面任一情况，它会自动把屏幕点亮：")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("• UU远程伴侣 意外退出")
                    Text("• UU远程伴侣 卡住超过 10 秒没反应")
                    Text("• UU远程 已经断开，屏幕却一直没亮")
                }
                .font(.callout)
                Text("就算这个小助手自己被关掉，系统也会在 5 秒内重新打开它。")
                    .font(.callout).foregroundStyle(.secondary)

                Divider()
                Text("需要你允许的事").font(.subheadline.bold())
                Text("打开后，macOS 会提示「已添加后台项目」，这是正常的。如果之后在「系统设置 › 通用 › 登录项与扩展」里关掉了 UU远程伴侣，守护就会失效，重新打开即可。它不需要其他权限；关掉这个开关，它就会被彻底移除。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { model.watchdogEnabled }, set: { model.toggleWatchdog($0) })) {
                        Text("打开后台守护")
                    }
                    .toggleStyle(.switch)
                    if model.watchdogEnabled {
                        Label(model.watchdogRunning ? "正在值守" : "没有运行",
                              systemImage: model.watchdogRunning ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.watchdogRunning ? .green : .orange)
                        if !model.watchdogRunning {
                            Button("去系统设置里允许") { SystemSettings.open(.loginItems) }
                        }
                    }
                }
            }

            if !model.watchdogEnabled {
                Label("没打开后台守护时：如果 UU远程伴侣 意外退出，屏幕可能会一直黑着。重新打开 UU远程伴侣 或重启 Mac 就能恢复。",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 整体

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    /// 离屏渲染时展开内容不放进 ScrollView（便于检查完整排版）
    var forRender = false

    @ViewBuilder private var expandedContent: some View {
        switch model.expanded {
        case .controller:
            WizardView(model: model.devices, openPermissions: model.openPermissions, embedded: true,
                       savedHint: model.savedHint) { model.saveDevices() }
                .frame(height: 500)
        case .controlled:
            ControlledPanel(model: model)
        case .fallback:
            if forRender {
                FallbackPanel(model: model)
            } else {
                ScrollView { FallbackPanel(model: model) }.frame(height: 520)
            }
        case .none:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 上：工作原理图
            HStack(alignment: .top, spacing: 0) {
                FlowNode(caption: "你的平板和手机", buttonTitle: "设置平板和手机",
                         selected: model.expanded == .controller, action: { model.toggle(.controller) }) {
                    ControllerIcon()
                }
                DashedConnector(label: "通过 UU远程 操控")
                FlowNode(caption: "这台 Mac", buttonTitle: "设置这台 Mac",
                         selected: model.expanded == .controlled, action: { model.toggle(.controlled) }) {
                    Image(systemName: "desktopcomputer")
                }
                DashedConnector(label: "熄灭 Mac 屏幕时")
                FlowNode(caption: "万一屏幕没亮", buttonTitle: "找回屏幕的方法",
                         enabled: model.fallbackAvailable, selected: model.expanded == .fallback,
                         hint: model.fallbackAvailable ? nil : "先在「设置这台 Mac」里打开「远程时熄灭 Mac 的屏幕」",
                         action: { model.toggle(.fallback) }) {
                    Image(systemName: "lifepreserver")
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)

            if model.expanded != nil {
                expandedContent
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            // 中：常用操作
            HStack(spacing: 14) {
                Button { model.restorePhysical?() } label: {
                    Label("立即恢复所有屏幕", systemImage: "display.2")
                }
                .disabled(!model.physicalOff)
                .help(model.physicalOff ? "也可以按 ⌃ control + ⌥ option + ⌘ command + 9" : "现在没有熄灭的屏幕")
                Button { model.openPermissions?() } label: { Label("权限设置", systemImage: "hand.raised") }
                Button { model.openTour?() } label: { Label("功能介绍", systemImage: "sparkles") }
            }
            .controlSize(.large)
            .padding(.vertical, 16)

            Divider()

            // 下：关于 / 完全退出
            HStack(spacing: 10) {
                Spacer()
                Button("关于 UU远程伴侣") { model.showAbout() }
                Button("完全退出", role: .destructive) { model.quitCompletely() }
                    .help("关闭 UU远程伴侣，后台守护也会一起停下（下次打开时恢复）")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 900)
        .clipped()
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?
    /// 自测用：当前设置窗口的模型与窗口
    var currentModel: SettingsModel? { model }
    var currentWindow: NSWindow? { window }
    var openPermissions: (() -> Void)?
    var openTour: (() -> Void)?
    var onConfigChanged: (() -> Void)?
    var setDisablePhysical: ((Bool) -> Void)?
    var setPaused: ((Bool) -> Void)?
    var restorePhysical: (() -> Void)?

    /// - Parameter pane: 打开时展开的面板，nil 表示全部收起
    func show(pane: SettingsPane? = nil) {
        if let window, let model {
            if let pane, model.expanded != pane { model.toggle(pane) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = SettingsModel()
        model.expanded = (pane == .fallback && !model.fallbackAvailable) ? nil : pane
        model.onConfigChanged = onConfigChanged
        model.setDisablePhysical = setDisablePhysical
        model.setPaused = setPaused
        model.restorePhysical = restorePhysical
        model.openPermissions = openPermissions
        model.openTour = openTour
        model.start()
        self.model = model
        // 用 NSHostingController 作为内容控制器：窗口尺寸随 SwiftUI 内容（展开/收起）自动调整。
        // 注意：直接给 NSHostingView 设 sizingOptions = .preferredContentSize 会让窗口初始尺寸为 0×0（看不见）
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.title = "UU远程伴侣 设置"
        w.isReleasedWhenClosed = false
        w.setContentSize(hosting.view.fittingSize)  // 先定好尺寸再居中，否则按 0×0 居中会偏到右侧
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            self?.model?.stop()
            self?.model = nil
            self?.window = nil
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 调试：渲染各状态为 PNG（--render-settings <目录>）
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, SettingsPane?, Bool, Bool)] = [
            ("collapsed-physical-off", nil, false, false),
            ("collapsed-physical-on", nil, true, false),
            ("controller", .controller, false, false),
            ("controlled", .controlled, true, false),
            ("fallback", .fallback, true, true),
        ]
        for (name, pane, physical, watchdog) in cases {
            let model = SettingsModel()
            model.autoVirtual = true
            model.disablePhysical = physical
            model.watchdogEnabled = watchdog
            model.watchdogRunning = false
            model.expanded = pane
            let view = NSHostingView(rootView: SettingsView(model: model, forRender: true))
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("settings-\(name).png"))
            }
        }
    }
}
