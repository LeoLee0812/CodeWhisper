import AppKit
import Carbon.HIToolbox

/// 剪贴板与自动粘贴。复制转录结果到剪贴板，并可选地模拟 ⌘V 直接粘贴到当前应用。
enum ClipboardManager {

    /// 复制文本到系统剪贴板。
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// 复制并模拟 ⌘V 粘贴到当前聚焦的应用。
    /// 需要「辅助功能」权限（CGEvent 发送按键）。
    static func copyAndPaste(_ text: String) {
        copy(text)
        // 给系统一点时间写入剪贴板，再发送粘贴按键
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulatePaste()
        }
    }

    private static func simulatePaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// 是否已获得辅助功能权限（自动粘贴与全局热键需要）。
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权提示并打开「辅助功能」设置。
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
