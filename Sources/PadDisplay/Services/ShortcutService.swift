import Carbon

/// 系统级快捷键只在用户开启时注册；不用后台键盘监听或事件注入。
@MainActor final class ShortcutService {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private var action: ((Int) -> Void)?

    func register(count: Int, action: @escaping (Int) -> Void) -> String? {
        stop(); self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr else { return result }
            MainActor.assumeIsolated {
                Unmanaged<ShortcutService>.fromOpaque(context).takeUnretainedValue().action?(Int(key.id))
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return "无法注册快捷键，请关闭后重试。" }
        let codes: [Int] = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                            kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_R]
        var failed = false
        for index in Array(0...min(count, 9)) + [10] {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x50414444, id: UInt32(index))
            let error = RegisterEventHotKey(UInt32(codes[index]), UInt32(cmdKey | controlKey | optionKey),
                                           id, GetApplicationEventTarget(), 0, &reference)
            if error == noErr, let reference { keys.append(reference) } else { failed = true }
        }
        return failed ? "部分快捷键已被其他软件占用；可继续使用菜单栏操作。" : nil
    }

    func stop() {
        keys.forEach { UnregisterEventHotKey($0) }; keys = []
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        action = nil
    }
}
