import AppKit
import SwiftUI

struct AboutView: View {
    static let author = "耳过清风"
    static let account = "5397290838"
    static let message = "本软件开源免费，欢迎点赞与关注，支持作者持续更新。"
    @State private var copied = false
    @State private var showingLicense = false

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var icon: NSImage? { Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) }

    var body: some View {
        VStack(spacing: 14) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 88, height: 88).accessibilityHidden(true) }
            else { Image(systemName: "display.2").font(.system(size: 60)).foregroundStyle(.blue).accessibilityHidden(true) }
            VStack(spacing: 6) {
                Text("PadDisplay").font(.system(size: 28, weight: .semibold))
                Text("让远程桌面，刚好适合你的屏幕。").font(.callout).foregroundStyle(.secondary)
                Text("版本 \(version)").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                Text("作者：\(Self.author) · 小红书号：\(Self.account)").font(.callout.weight(.medium)).textSelection(.enabled)
                Text(Self.message).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 6)
            Button(copied ? "已复制" : "复制小红书号", systemImage: copied ? "checkmark" : "doc.on.doc") {
                NSPasteboard.general.clearContents()
                copied = NSPasteboard.general.setString(Self.account, forType: .string)
            }.appButton().disabled(copied)
            Button("MIT 开源许可") { showingLicense = true }.buttonStyle(.link).font(.caption)
        }.padding(30).frame(width: 560)
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)); copied = false } catch {}
        }
        .sheet(isPresented: $showingLicense) { LicenseView() }
    }
}

private struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    private var text: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return "许可文件未能读取，请检查应用安装包。" }
        let notice = Bundle.main.url(forResource: "ASSET-NOTICE", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return notice.isEmpty ? contents : contents + "\n\n" + notice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MIT 开源许可").font(.title2.weight(.semibold))
            ScrollView { Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Spacer(); Button("完成") { dismiss() }.appButton(prominent: true).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 620, height: 430)
    }
}
