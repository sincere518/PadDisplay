// 菜单栏：状态 / 设置 / 默认设备 / 暂停 / 开机自启 / 退出
import AppKit
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: Coordinator
    private let openSettings: (SettingsPane?) -> Void
    private let openPermissions: () -> Void
    private let openTour: () -> Void
    private let store = ConfigStore.shared

    init(coordinator: Coordinator, openSettings: @escaping (SettingsPane?) -> Void, openPermissions: @escaping () -> Void,
         openTour: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettings = openSettings
        self.openPermissions = openPermissions
        self.openTour = openTour
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        // 关闭自动启用，否则「立即恢复所有屏幕」等项设置的 isEnabled 会被覆盖（没熄灭屏幕时也可点）
        menu.autoenablesItems = false
        item.menu = menu
        refresh()
    }

    /// 菜单栏图标：Assets/AppIcon/MenuBarIconTemplate（模板图，深色菜单栏自动反白）；
    /// 非 .app 运行（调试）找不到资源时退回系统图标
    private static let menuBarIcon: NSImage = {
        if let image = NSImage(named: "MenuBarIconTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)!
    }()

    func refresh() {
        let icon = StatusBarController.menuBarIcon
        icon.accessibilityDescription = "UU远程伴侣"
        item.button?.image = icon
        item.button?.appearsDisabled = store.config.paused  // 暂停自动切换时图标变灰
        item.button?.toolTip = "UU远程伴侣：\(coordinator.statusText)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: coordinator.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if !UUReader.isTrusted {
            let warn = NSMenuItem(title: "⚠️ 还没授权，认不出连接的设备", action: #selector(showPermissions), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        if store.config.shouldDisablePhysical && store.config.shouldRunWatchdog && !Watchdog.isRunning {
            let warn = NSMenuItem(title: "⚠️ 后台守护已打开，但没有运行", action: #selector(showDisplaySettings), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        let restore = action("立即恢复所有屏幕（⌃⌥⌘+9）", #selector(restorePhysical))
        restore.isEnabled = coordinator.display.physicalOff || PhysicalDisplays.pending != nil
        menu.addItem(restore)
        let physical = action("远程时熄灭 Mac 屏幕", #selector(toggleDisablePhysical))
        physical.state = store.config.shouldDisablePhysical ? .on : .off
        menu.addItem(physical)
        menu.addItem(.separator())

        menu.addItem(action("设置…", #selector(reconfigure), key: ","))
        menu.addItem(action("权限设置…", #selector(showPermissions)))
        menu.addItem(action("功能介绍…", #selector(showTour)))

        let defaults = NSMenuItem(title: "默认设备", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let none = action("不调整", #selector(pickDefault(_:)))
        none.representedObject = ""
        none.state = store.config.defaultDevice == nil ? .on : .off
        sub.addItem(none)
        for d in store.config.devices where d.kind != .computer {
            let it = action("\(d.name)（\(d.sizeLabel)）", #selector(pickDefault(_:)))
            it.representedObject = d.name
            it.state = store.config.defaultDevice == d.name ? .on : .off
            sub.addItem(it)
        }
        defaults.submenu = sub
        menu.addItem(defaults)

        let pause = action("暂停自动切换", #selector(togglePause))
        pause.state = store.config.paused ? .on : .off
        menu.addItem(pause)

        let login = action("开机时自动打开", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(action("退出", #selector(quit), key: "q"))
    }

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        return it
    }

    @objc private func reconfigure() { openSettings(nil) }

    @objc private func showDisplaySettings() { openSettings(.fallback) }

    @objc private func restorePhysical() { coordinator.restorePhysical() }

    @objc private func toggleDisablePhysical() { coordinator.setDisablePhysical(!store.config.shouldDisablePhysical) }

    @objc private func showPermissions() { openPermissions() }

    @objc private func showTour() { openTour() }


    @objc private func pickDefault(_ sender: NSMenuItem) {
        let name = sender.representedObject as? String ?? ""
        store.config.defaultDevice = name.isEmpty ? nil : name
        refresh()
    }

    @objc private func togglePause() {
        coordinator.setPaused(!store.config.paused)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.info("⚠️ 开机自启设置失败：\(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "开机自动打开没有设置成功"
            alert.informativeText = "\(error.localizedDescription)\n请先把 UU远程伴侣 放进「应用程序」文件夹，再试一次。"
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
