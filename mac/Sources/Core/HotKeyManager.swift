import AppKit
import Carbon.HIToolbox

/// 全局热键管理：实现「按住录音、松开停止」(hold-to-record)。
/// 通过 NSEvent 全局监听键盘事件，需要「辅助功能」权限。
@MainActor
final class HotKeyManager {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isHeld = false

    private var keyCode: Int = kVK_ANSI_M
    private var requiredFlags: NSEvent.ModifierFlags = .command

    /// 用当前设置注册监听。
    func register(keyCode: Int, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.requiredFlags = Self.flags(fromCarbon: carbonModifiers)
        unregister()

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // 本地监听确保 app 自身聚焦时也能用，并避免事件吞掉
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        isHeld = false
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard !isHeld, Int(event.keyCode) == keyCode, modifiersMatch(event) else { return }
            isHeld = true
            onPress()
        case .keyUp:
            guard isHeld, Int(event.keyCode) == keyCode else { return }
            isHeld = false
            onRelease()
        case .flagsChanged:
            // 若在按住期间松开了修饰键，也视为结束录音
            if isHeld && !modifiersMatch(event) {
                isHeld = false
                onRelease()
            }
        default:
            break
        }
    }

    private func modifiersMatch(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let active = event.modifierFlags.intersection(relevant)
        return active.isSuperset(of: requiredFlags)
    }

    private static func flags(fromCarbon carbon: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        let c = UInt32(carbon)
        if c & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if c & UInt32(optionKey) != 0 { flags.insert(.option) }
        if c & UInt32(controlKey) != 0 { flags.insert(.control) }
        if c & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}
