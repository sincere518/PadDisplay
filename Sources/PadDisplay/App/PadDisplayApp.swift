import AppKit
import SwiftUI

@main struct PadDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("PadDisplay · 远程桌面助手", id: "main") {
            ContentView(model: model)
        }.defaultSize(width: 1040, height: 720).windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 PadDisplay") { openWindow(id: "about") }
            }
        }
        Window("关于 PadDisplay", id: "about") { AboutView() }.windowResizability(.contentSize)
        MenuBarExtra(model.isValidation ? "PadDisplay UI验证" : "PadDisplay", systemImage: "display.2") { MenuContent(model: model) }
        Settings { SettingsView(model: model) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false
    private var displayTest: DisplaySelfTest?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppController.shared.isValidation,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.PadDisplay")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate()
            terminating = true
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments
        if AppController.shared.isValidation {
            NSApp.appearance = NSAppearance(named: args.contains("dark") ? .darkAqua : .aqua)
            AppController.shared.start()
            return
        }
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
