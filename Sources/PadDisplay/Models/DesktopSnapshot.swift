import CoreGraphics
import Foundation

struct SavedDisplayMode: Codable {
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let modeID: Int32

    init(_ mode: CGDisplayMode) {
        width = mode.width; height = mode.height
        pixelWidth = mode.pixelWidth; pixelHeight = mode.pixelHeight
        refreshRate = mode.refreshRate; modeID = mode.ioDisplayModeID
    }

    func matches(_ mode: CGDisplayMode) -> Bool {
        width == mode.width && height == mode.height && pixelWidth == mode.pixelWidth && pixelHeight == mode.pixelHeight &&
        (refreshRate == 0 || abs(refreshRate - mode.refreshRate) < 0.6)
    }
}

struct SavedDisplay: Codable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let x: Int32
    let y: Int32
    let mode: SavedDisplayMode?
    let mirrorOf: CGDirectDisplayID?
    let main: Bool?

    init(_ id: CGDirectDisplayID) {
        self.id = id; vendor = CGDisplayVendorNumber(id); model = CGDisplayModelNumber(id)
        serial = CGDisplaySerialNumber(id)
        x = Int32(CGDisplayBounds(id).minX); y = Int32(CGDisplayBounds(id).minY)
        mode = CGDisplayCopyDisplayMode(id).map(SavedDisplayMode.init)
        mirrorOf = CGDisplayMirrorsDisplay(id); main = CGDisplayIsMain(id) != 0
    }

    func resolve(in online: [CGDirectDisplayID], allowFallback: Bool = true) -> CGDirectDisplayID? {
        let matches = online.filter {
            CGDisplayVendorNumber($0) == vendor && CGDisplayModelNumber($0) == model && CGDisplaySerialNumber($0) == serial
        }
        if matches.contains(id) { return id }
        return allowFallback && matches.count == 1 ? matches.first : nil
    }
}

struct DesktopSnapshot: Codable {
    let format: Int
    let displays: [SavedDisplay]
    let windows: [SavedWindow]

    init(displays: [SavedDisplay], windows: [SavedWindow]) { format = 1; self.displays = displays; self.windows = windows }

    static func read(_ data: Data) throws -> DesktopSnapshot {
        // 0.2.x 的记录是位置数组，缺失的模式信息保持原样。
        let snapshot: DesktopSnapshot
        if let old = try? JSONDecoder().decode([SavedDisplay].self, from: data) {
            snapshot = DesktopSnapshot(displays: old, windows: [])
        } else { snapshot = try JSONDecoder().decode(Self.self, from: data) }
        guard snapshot.format == 1, snapshot.displays.count <= 64, snapshot.windows.count <= 200,
              Set(snapshot.displays.map(\.id)).count == snapshot.displays.count,
              snapshot.displays.allSatisfy({ $0.id != 0 }) else {
            throw NSError(domain: "PadDisplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "桌面恢复记录版本或内容无效。"])
        }
        return snapshot
    }
}
