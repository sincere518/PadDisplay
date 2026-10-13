import AppKit
import SwiftUI

@main struct PadDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppController.shared

    var body: some Scene {
        WindowGroup("PadDisplay · 远程桌面助手", id: "main") {
            ContentView(model: model)
        }.windowResizability(.contentMinSize)
        MenuBarExtra("PadDisplay", systemImage: "display.2") { MenuContent(model: model) }
        Settings {
            VStack(alignment: .leading, spacing: 16) {
                Text("PadDisplay").font(.title2.bold())
                Toggle("登录 Mac 时自动打开", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                Text("设备与分辨率在主窗口中设置。关闭窗口后，软件继续在菜单栏运行。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 360)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false
    private var displayTest: DisplaySelfTest?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.PadDisplay")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            terminating = true
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--diagnose"), index + 1 < args.count {
            let reader = UUConnectionReader()
            reader.sample { reading in
                Diagnostics.write(["authorized": UUConnectionReader.authorized,
                                   "controllers": reading.controllers as Any? ?? NSNull(),
                                   "detail": reading.detail, "screens": Diagnostics.screens()],
                                  to: URL(fileURLWithPath: args[index + 1]))
                self.terminating = true
                NSApp.terminate(nil)
            }
            return
        }
        if let index = args.firstIndex(of: "--display-self-test"), index + 1 < args.count {
            guard !AppController.shared.companionRunning else {
                Diagnostics.write(["success": false, "error": "请先退出 UU伴侣再自测"],
                                  to: URL(fileURLWithPath: args[index + 1]))
                terminating = true
                NSApp.terminate(nil)
                return
            }
            displayTest = DisplaySelfTest(output: URL(fileURLWithPath: args[index + 1])) {
                self.terminating = true
                NSApp.terminate(nil)
            }
            displayTest?.run()
            return
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { finish() }
        return .terminateCancel
    }
}
