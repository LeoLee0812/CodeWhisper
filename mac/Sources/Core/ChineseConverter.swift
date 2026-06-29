import Foundation

/// 中文文本后处理：繁体转简体、标点规范化。
/// 对应 Python 版的 utils.convert_to_simplified_chinese / normalize_zh_punctuation。
enum ChineseConverter {

    /// 繁体中文转简体中文。使用系统 ICU 的 Hant-Hans transform，无需第三方依赖。
    static func toSimplified(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let transform = StringTransform(rawValue: "Hant-Hans")
        return text.applyingTransform(transform, reverse: false) ?? text
    }

    /// 规范化中文标点：把英文逗号替换为中文逗号。
    static func normalizePunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.replacingOccurrences(of: ",", with: "，")
    }
}
