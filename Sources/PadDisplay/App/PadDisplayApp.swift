import AppKit
import SwiftUI
import PadDisplayCore

@main struct PadDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("PadDisplay · 远程桌面助手", id: "main") {
            ContentView(model: model)
                .onOpenURL { model.handleShortcut($0) }
        }.defaultSize(width: 1040, height: 720).windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 PadDisplay") { openWindow(id: "about") }
            }
            CommandMenu("屏幕") {
                Button("恢复原桌面") { model.restore() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.report.busy)
                Button("继续自动匹配") { model.resumeAutomatic() }
                if let profile = model.currentProfile {
                    Button("切换横竖屏") { model.rotate(profile) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.report.busy)
                    Menu("显示预设") {
                        ForEach(DesktopDensity.allCases, id: \.self) { density in
                            Button(density.label) { model.setDensity(density, for: profile) }
                        }
                    }.disabled(model.report.busy)
                }
                Divider()
                ForEach(Array(model.favorites.enumerated()), id: \.element.id) { index, profile in
                    Button(String(profile.displayTitle.prefix(24))) { model.useManually(profile) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control, .option])
                        .disabled(model.report.busy)
                }
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { model.updates.check(); openWindow(id: "updates") }
            }
        }
        Window("关于 PadDisplay", id: "about") { AboutView() }.windowResizability(.contentSize)
        Window("连接助手", id: "connection") { ConnectionAssistantView(model: model) }.windowResizability(.contentSize)
        Window("PadDisplay 更新", id: "updates") { UpdateView(model: model).frame(width: 600, height: 500) }.windowResizability(.contentSize)
        MenuBarExtra("PadDisplay", systemImage: "display.2") { MenuContent(model: model) }
        Settings { SettingsView(model: model) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--diagnose"), index + 1 < args.count {
            let reader = UUConnectionReader()
            reader.sample { reading in
                Diagnostics.write(["authorized": UUConnectionReader.authorized,
                                   "controllers": reading.controllers as Any? ?? NSNull(),
                                   "controllerCount": reading.controllerCount as Any? ?? NSNull(),
                                   "detail": reading.detail, "screens": Diagnostics.screens()],
                                  to: URL(fileURLWithPath: args[index + 1]))
                self.terminating = true
                NSApp.terminate(nil)
            }
            return
        }
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.PadDisplay")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            terminating = true
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppController.shared.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        terminating = true
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            NSApp.terminate(nil)
        }
        AppController.shared.shutdown(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { finish() }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) { AppController.shared.updates.cleanTemporary() }
}
