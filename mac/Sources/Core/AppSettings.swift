import Foundation
import Carbon.HIToolbox
import Combine

/// 转录触发后的输出行为。
enum OutputMode: String, CaseIterable, Identifiable {
    case copyOnly      // 仅复制到剪贴板
    case copyAndPaste  // 复制并自动粘贴到当前应用
    var id: String { rawValue }
    var label: String {
        switch self {
        case .copyOnly: return "仅复制到剪贴板"
        case .copyAndPaste: return "复制并自动粘贴"
        }
    }
}

/// 用户设置，持久化到 UserDefaults。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// WhisperKit 模型名（HuggingFace 上的标识，如 openai_whisper-large-v3-v20240930_turbo）。
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: "modelName") }
    }

    /// 转录语言（zh / en / auto）。
    @Published var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }

    /// 输出方式：仅复制 / 复制并粘贴。
    @Published var outputMode: OutputMode {
        didSet { defaults.set(outputMode.rawValue, forKey: "outputMode") }
    }

    /// 是否启用术语纠正。
    @Published var fixTerms: Bool {
        didSet { defaults.set(fixTerms, forKey: "fixTerms") }
    }

    /// 是否开机自启。
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    /// 录音完成提示音。
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }

    /// 全局热键：键码。
    @Published var hotKeyCode: Int {
        didSet { defaults.set(hotKeyCode, forKey: "hotKeyCode") }
    }

    /// 全局热键：修饰键（Carbon modifier flags）。
    @Published var hotKeyModifiers: Int {
        didSet { defaults.set(hotKeyModifiers, forKey: "hotKeyModifiers") }
    }

    private init() {
        modelName = defaults.string(forKey: "modelName") ?? "openai_whisper-large-v3-v20240930_turbo_632MB"
        language = defaults.string(forKey: "language") ?? "zh"
        outputMode = OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "")
            ?? .copyAndPaste
        fixTerms = defaults.object(forKey: "fixTerms") as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        playSound = defaults.object(forKey: "playSound") as? Bool ?? true
        hotKeyCode = defaults.object(forKey: "hotKeyCode") as? Int ?? kVK_ANSI_M
        hotKeyModifiers = defaults.object(forKey: "hotKeyModifiers") as? Int ?? Int(cmdKey)
    }

    /// 人类可读的热键描述，例如 "⌘M"。
    var hotKeyDescription: String {
        var parts = ""
        let mods = UInt32(hotKeyModifiers)
        if mods & UInt32(controlKey) != 0 { parts += "⌃" }
        if mods & UInt32(optionKey) != 0 { parts += "⌥" }
        if mods & UInt32(shiftKey) != 0 { parts += "⇧" }
        if mods & UInt32(cmdKey) != 0 { parts += "⌘" }
        parts += KeyCodeNames.name(for: hotKeyCode)
        return parts
    }
}

/// 键码到可读名称的简单映射。
enum KeyCodeNames {
    static func name(for code: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_Space: "Space",
        ]
        return map[code] ?? "Key\(code)"
    }
}
