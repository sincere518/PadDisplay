// UU远程伴侣：本机被 UU远程 控制时，按控制端设备自动建虚拟屏并设为主屏，断开后还原
// 调试：UUDisplay --simulate "<设备名>" [秒数=10]  模拟一次连入/断开（不依赖 UU）
//      UUDisplay --simulate "A>B" 8            先按 A 建屏，3 秒后识别为 B 重建
//      UUDisplay --render-settings <目录>       渲染设置窗口各面板为 PNG
//      UUDisplay --dump-devices                打印从 UU 读到的设备及预填配置
//      UUDisplay --watchdog                    看门狗模式（由 launchd 托管）
//      UUDisplay --render-tour <目录>           渲染功能导览配图（Assets/Tour）
//      UUDisplay --tour                        只展示功能导览
import AppKit
import Carbon.HIToolbox
import PermissionFlow
import ServiceManagement
import SwiftUI

if CommandLine.arguments.contains("--watchdog") { Watchdog.run() }

if CommandLine.arguments.contains("--dump-devices") {
    if !UUReader.hasMainWindow { UUReader.showMainWindow(); Thread.sleep(forTimeInterval: 1) }
    guard let devices = UUReader.readDevices() else { print("未读到 UU 主窗口"); exit(1) }
    for d in devices {
        let cfg = DeviceConfig.make(name: d.name, kind: Presets.guessKind(name: d.name, isComputerGroup: d.isComputerGroup))
        let size = cfg.kind == .computer ? "不切换" : cfg.sizeLabel
        print("\(d.isSelf ? "（本机，排除）" : "")\(d.name)\t→ \(cfg.kind.label)\t\(size)")
    }
    print("控制端：\(UUReader.readControllers() ?? [])")
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = Coordinator()
    let settings = SettingsWindowController()
    let permissions = PermissionsWindowController()
    let tour = TourController()
    var statusBar: StatusBarController?
    private var heartbeatTimer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var demoController: PermissionFlowController?
    private var terminating = false

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.info("启动 UUDisplay，辅助功能权限：\(UUReader.isTrusted)")
        statusBar = StatusBarController(coordinator: coordinator,
                                        openSettings: { [weak self] in self?.settings.show(pane: $0) },
                                        openPermissions: { [weak self] in self?.permissions.show() },
                                        openTour: { [weak self] in self?.tour.show() })
        settings.openPermissions = { [weak self] in self?.permissions.show() }
        settings.onConfigChanged = { [weak self] in self?.coordinator.configChanged() }
        settings.setDisablePhysical = { [weak self] in self?.coordinator.setDisablePhysical($0) }
        settings.setPaused = { [weak self] in self?.coordinator.setPaused($0) }
        settings.restorePhysical = { [weak self] in self?.coordinator.restorePhysical() }
        settings.openTour = { [weak self] in self?.tour.show() }
        coordinator.onChange = { [weak self] in self?.statusBar?.refresh() }

        // 心跳：看门狗据此判断主程序是否卡死（主线程定时器，卡住即停跳）
        Heartbeat.beat(Heartbeat.appURL)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in Heartbeat.beat(Heartbeat.appURL) }
        installHotkey()

        let args = CommandLine.arguments
        // 调试：渲染设置窗口各面板后退出：--render-settings <目录>
        if let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
            SettingsWindowController.render(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        // 调试：渲染 TourKit 导览界面（逐页）后退出：--render-tour-ui <配图目录> <输出目录>
        if let i = args.firstIndex(of: "--render-tour-ui"), i + 2 < args.count {
            Tour.renderUI(imagesDir: URL(fileURLWithPath: args[i + 1]), to: URL(fileURLWithPath: args[i + 2]))
            exit(0)
        }
        // 调试：渲染功能导览配图后退出
        if let i = args.firstIndex(of: "--render-tour"), i + 1 < args.count {
            Tour.render(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        // 调试：把权限窗口渲染为 PNG 后退出
        if let i = args.firstIndex(of: "--render-permissions"), i + 1 < args.count {
            let model = PermissionsModel()
            if ProcessInfo.processInfo.environment["UUDISPLAY_RENDER_PENDING"] == "1" {
                model.axGranted = false
            }
            let view = NSHostingView(rootView: PermissionsView(model: model) {})
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
                }
                exit(0)
            }
            return
        }
        // 调试：直接走「授权」按钮背后的 PermissionFlow 调用（打开系统设置 + 拖拽面板）
        if args.contains("--demo-authorize") {
            let url = Bundle.main.bundleURL
            demoController = PermissionFlowController(configuration: .init(
                requiredAppURLs: [url], promptForAccessibilityTrust: false, localeIdentifier: "zh-Hans"))
            demoController?.authorize(pane: .accessibility, suggestedAppURLs: [url],
                                      sourceFrameInScreen: CGRect(x: 800, y: 500, width: 32, height: 32))
            return
        }
        if let i = args.firstIndex(of: "--stress"), i + 1 < args.count, let n = Int(args[i + 1]) {
            stress(rounds: n)
            return
        }
        if args.contains("--selftest-settings") {
            selfTestSettings()
            return
        }
        if let i = args.firstIndex(of: "--simulate"), i + 1 < args.count {
            simulate(name: args[i + 1], seconds: i + 2 < args.count ? Double(args[i + 2]) ?? 10 : 10)
            return
        }

        if args.contains("--tour") {
            tour.show { NSApp.terminate(nil) }
            return
        }

        registerWatchdog()
        coordinator.start()
        // 首次启动先看功能导览；缺权限再走授权引导，完成（或稍后再说）后进入设备配置
        let configure = { [weak self] in
            if !ConfigStore.shared.isConfigured { self?.settings.show(pane: .controller) }
        }
        let setup = { [weak self] in
            guard let self else { return }
            if PermissionsModel.allGranted {
                configure()
            } else {
                self.permissions.show(autoClose: true, onDone: configure)
            }
        }
        if ConfigStore.shared.config.tourShown == true {
            setup()
        } else {
            tour.show(onDone: setup)
        }
    }

    /// 退出前异步收尾（恢复物理屏、移除虚拟屏、还原布局）。
    /// 注意：.terminateLater 期间主队列的延时任务不会执行，收尾会卡住；
    /// 所以先取消本次退出，收尾完成后再真正退出（最多等 8 秒，残留由看门狗兜底）。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        terminating = true
        var done = false
        let finish = {
            guard !done else { return }
            done = true
            Log.info("退出 UUDisplay")
            NSApp.terminate(nil)
        }
        coordinator.shutdown(completion: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: finish)
        return .terminateCancel
    }

    /// 看门狗以 LaunchAgent 形式安装（KeepAlive）：仅当用户在设置里开启时安装，否则确保已卸载
    private func registerWatchdog() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            Log.info("非 .app 运行，跳过看门狗安装（可手动运行 --watchdog）")
            return
        }
        if ConfigStore.shared.config.shouldRunWatchdog {
            WatchdogAgent.ensureInstalled()
        } else {
            WatchdogAgent.uninstall()
        }
    }

    /// 全局快捷键 ⌃⌥⌘9：立即恢复物理屏（Carbon 热键，无需任何权限）
    private func installHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            guard let ctx else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { delegate.coordinator.restorePhysical() }
            return noErr
        }, 1, &spec, me, nil)
        let id = EventHotKeyID(signature: OSType(0x5555_4453), id: 1)  // 'UUDS'
        let err = RegisterEventHotKey(UInt32(kVK_ANSI_9), UInt32(cmdKey | optionKey | controlKey), id,
                                      GetApplicationEventTarget(), 0, &hotKeyRef)
        Log.info(err == noErr ? "已注册快捷键 ⌃⌥⌘9" : "⚠️ 快捷键 ⌃⌥⌘9 注册失败 \(err)")
    }

    /// 自测：打开设置窗口，依次调用各按钮背后的操作，检查配置变化与窗口尺寸（不经过鼠标点击）
    private func selfTestSettings() {
        coordinator.display.shouldDisablePhysical = { [weak self] in self?.coordinator.physicalDisableAllowed ?? false }
        let store = ConfigStore.shared
        var steps: [(String, () -> Void, () -> String?)] = []   // 名称、操作、检查（返回 nil 表示通过）
        var results: [String] = []
        var heights: [String: CGFloat] = [:]
        func m() -> SettingsModel { settings.currentModel! }
        func h() -> CGFloat { settings.currentWindow?.frame.height ?? 0 }
        var openedPermissions = false, openedTour = false, restored = false
        settings.openPermissions = { openedPermissions = true }
        settings.openTour = { openedTour = true }
        settings.restorePhysical = { restored = true }

        steps.append(("打开设置窗口", { self.settings.show() }, {
            heights["收起"] = h(); return h() > 200 ? nil : "窗口高度 \(h())" }))
        steps.append(("展开「设置平板和手机」", { m().toggle(.controller) }, {
            heights["设备"] = h(); return (m().expanded == .controller && h() > heights["收起"]! + 300) ? nil : "expanded=\(String(describing: m().expanded)) 高度=\(h())" }))
        steps.append(("再点一次收起", { m().toggle(.controller) }, {
            (m().expanded == nil && abs(h() - heights["收起"]!) < 2) ? nil : "高度=\(h())" }))
        steps.append(("展开「设置这台 Mac」", { m().toggle(.controlled) }, {
            (m().expanded == .controlled && h() > heights["收起"]! + 150) ? nil : "高度=\(h())" }))
        steps.append(("「找回屏幕的方法」在熄灭开关关闭时不可展开", { m().toggleDisablePhysical(false); m().toggle(.fallback) }, {
            (!m().fallbackAvailable && m().expanded == .controlled) ? nil : "expanded=\(String(describing: m().expanded))" }))
        steps.append(("关闭「自动准备虚拟屏幕」", { m().toggleAutoVirtual(false) }, {
            (store.config.paused && !m().fallbackAvailable) ? nil : "paused=\(store.config.paused)" }))
        steps.append(("打开「自动准备虚拟屏幕」", { m().toggleAutoVirtual(true) }, {
            !store.config.paused ? nil : "paused 仍为 true" }))
        steps.append(("打开「远程时熄灭 Mac 的屏幕」", { m().toggleDisablePhysical(true) }, {
            (store.config.shouldDisablePhysical && m().fallbackAvailable) ? nil : "disablePhysical=\(store.config.shouldDisablePhysical)" }))
        steps.append(("展开「找回屏幕的方法」", { m().toggle(.fallback) }, {
            heights["找回"] = h(); return (m().expanded == .fallback && h() > heights["收起"]! + 300) ? nil : "高度=\(h())" }))
        steps.append(("关闭熄灭开关时自动收起「找回屏幕的方法」", { m().toggleDisablePhysical(false) }, {
            (m().expanded == nil && !store.config.shouldDisablePhysical) ? nil : "expanded=\(String(describing: m().expanded))" }))
        steps.append(("打开后台守护", { m().toggleDisablePhysical(true); m().toggleWatchdog(true) }, {
            (store.config.shouldRunWatchdog && WatchdogAgent.isLoaded) ? nil : "已加载=\(WatchdogAgent.isLoaded)" }))
        steps.append(("后台守护开始值守（等心跳）", { RunLoop.main.run(until: Date().addingTimeInterval(4)); m().refresh() }, {
            m().watchdogRunning ? nil : "watchdogRunning=false" }))
        steps.append(("关闭后台守护", { m().toggleWatchdog(false) }, {
            (!store.config.shouldRunWatchdog && !WatchdogAgent.isLoaded) ? nil : "仍已加载" }))
        steps.append(("「立即恢复所有屏幕」按钮", { m().restorePhysical?() }, { restored ? nil : "未调用" }))
        steps.append(("「权限设置」按钮", { m().openPermissions?() }, { openedPermissions ? nil : "未调用" }))
        steps.append(("「功能介绍」按钮", { m().openTour?() }, { openedTour ? nil : "未调用" }))
        steps.append(("「关于 UU远程伴侣」按钮", { m().showAbout() }, {
            NSApp.windows.contains { $0.isVisible && $0 !== self.settings.currentWindow && $0.frame.width > 200 } ? nil : "没有出现关于面板" }))
        steps.append(("设备配置「保存」按钮", { m().saveDevices() }, { m().savedHint ? nil : "没有显示「已保存」" }))

        var i = 0
        func next() {
            guard i < steps.count else {
                Log.info("—— 设置窗口自测完成：\(results.filter { $0.hasPrefix("✅") }.count)/\(steps.count) 通过")
                results.forEach { Log.info($0) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
                return
            }
            let (name, act, check) = steps[i]
            act()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let r = check()
                results.append(r == nil ? "✅ \(name)" : "❌ \(name)：\(r!)")
                i += 1
                next()
            }
        }
        next()
    }

    /// 压测：随机连入/换设备/断开，间隔 0.3–6 秒，制造上一轮未收尾就进入下一轮的情况
    private func stress(rounds: Int) {
        coordinator.display.shouldDisablePhysical = { [weak self] in self?.coordinator.physicalDisableAllowed ?? false }
        coordinator.display.recoverIfNeeded()
        let devices = ["iPad Air", "OPPO Pad 3 Pro", "iPhone 17", "OPPO Reno13 Pro", "M1"]
        // UUDISPLAY_STRESS_SLOW=1：每段停留 2.5–5 秒，确保走到关闭物理屏
        let slow = ProcessInfo.processInfo.environment["UUDISPLAY_STRESS_SLOW"] == "1"
        func hold(_ r: ClosedRange<Double>) -> Double { slow ? Double.random(in: 2.5...5) : Double.random(in: r) }
        var t = 0.0
        for r in 1...rounds {
            let a = devices.randomElement()!
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                Log.info("—— 压测第 \(r)/\(rounds) 轮：连入 \(a)")
                self?.coordinator.simulatedName = a
                self?.coordinator.handleConnect()
            }
            t += hold(0.3...4)
            if Bool.random() {
                let b = devices.randomElement()!
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                    Log.info("—— 换设备为 \(b)")
                    self?.coordinator.simulatedName = b
                    self?.coordinator.handleConnect()
                }
                t += hold(0.3...3)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                Log.info("—— 断开")
                self?.coordinator.handleDisconnect()
                self?.coordinator.simulatedName = nil
            }
            t += hold(0.3...6)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 1) {
            Log.info("—— 压测结束，退出")
            NSApp.terminate(nil)
        }
    }

    private func simulate(name: String, seconds: Double) {
        coordinator.display.shouldDisablePhysical = { [weak self] in self?.coordinator.physicalDisableAllowed ?? false }
        coordinator.display.recoverIfNeeded()
        // "A>B"：先按 A 连入，3 秒后识别为 B（模拟名称延迟出现导致的重建）
        let names = name.components(separatedBy: ">")
        Log.info("模拟连入：\(name)，\(Int(seconds)) 秒后断开")
        coordinator.simulatedName = names[0]
        coordinator.handleConnect()
        if names.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.coordinator.simulatedName = names[1]
                self?.coordinator.handleConnect()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.coordinator.handleDisconnect()
            self?.coordinator.simulatedName = nil
            Log.info("模拟断开完成")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }  // 顶层代码运行在主线程
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
