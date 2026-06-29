import Foundation

/// 一次术语修正的记录。
struct Correction: Hashable {
    let wrong: String
    let correct: String
    let category: String
}

/// 术语字典管理器：加载 programmer_terms.json，对转录文本做开发者术语纠正。
/// 对应 Python 版 dict_manager.DictionaryManager。
final class DictionaryManager {

    /// 编译后的单条替换规则。
    private struct Rule {
        let regex: NSRegularExpression
        let correct: String
        let category: String
        let wrongLen: Int
    }

    private var rules: [Rule] = []

    /// 所有正确术语（correct 字段），用于生成 Whisper 提示词与术语检测。
    private(set) var correctTerms: [String] = []

    init() {
        loadDictionary()
    }

    // MARK: - 加载与解析

    private func loadDictionary() {
        guard let url = Bundle.main.url(forResource: "programmer_terms", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            CWLog.warn("字典文件不存在，跳过术语纠正")
            return
        }

        guard let root = try? JSONDecoder().decode(TermDictFile.self, from: data) else {
            CWLog.warn("字典解析失败")
            return
        }

        var built: [Rule] = []
        var terms = Set<String>()

        for (categoryName, category) in root.categories {
            for (_, term) in category.terms {
                let correct = term.correct
                if !correct.isEmpty { terms.insert(correct) }
                for variant in term.variants {
                    let wrong = variant.wrong
                    guard !wrong.isEmpty else { continue }
                    guard let regex = Self.makeRegex(for: wrong) else { continue }
                    built.append(Rule(regex: regex, correct: correct,
                                      category: categoryName, wrongLen: wrong.count))
                }
            }
        }

        // 按错误文本长度降序：先匹配长词，避免短词覆盖长词。
        rules = built.sorted { $0.wrongLen > $1.wrongLen }
        correctTerms = terms.sorted()
        CWLog.info("已加载术语规则 \(rules.count) 条，术语 \(correctTerms.count) 个")
    }

    /// 为某个错误拼写构建正则。短的纯字母数字词（≤3）加前后边界，避免子串误匹配。
    private static func makeRegex(for wrong: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: wrong)
        let isShortAlnum = wrong.count <= 3 &&
            wrong.range(of: "^[a-zA-Z0-9]+$", options: .regularExpression) != nil
        let pattern = isShortAlnum
            ? "(?<![a-zA-Z0-9])\(escaped)(?![a-zA-Z0-9])"
            : escaped
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: - 文本修正

    /// 修正文本中的开发者术语，返回修正后文本与修正记录。
    func fix(_ input: String) -> (text: String, corrections: [Correction]) {
        guard !input.isEmpty, !rules.isEmpty else { return (input, []) }

        var ns = input as NSString
        var protectedRanges: [NSRange] = []   // 已替换区域，避免后续规则二次破坏
        var corrections: [Correction] = []

        for rule in rules {
            let fullRange = NSRange(location: 0, length: ns.length)
            let matches = rule.regex.matches(in: ns as String, range: fullRange)
            // 从后往前替换，避免位置偏移
            for match in matches.reversed() {
                let range = match.range
                let matched = ns.substring(with: range)
                if matched == rule.correct { continue }
                if protectedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                    continue
                }

                ns = ns.replacingCharacters(in: range, with: rule.correct) as NSString
                let replacementLen = (rule.correct as NSString).length
                let delta = replacementLen - range.length
                let tail = range.location + range.length
                // 位于替换点之后的受保护区间需要整体平移
                protectedRanges = protectedRanges.map { pr in
                    pr.location >= tail
                        ? NSRange(location: pr.location + delta, length: pr.length)
                        : pr
                }
                protectedRanges.append(NSRange(location: range.location, length: replacementLen))
                corrections.append(Correction(wrong: matched, correct: rule.correct, category: rule.category))
            }
        }

        return (ns as String, corrections)
    }
}

// MARK: - JSON 模型

private struct TermDictFile: Decodable {
    let categories: [String: Category]
}

private struct Category: Decodable {
    let terms: [String: Term]
}

private struct Term: Decodable {
    let correct: String
    let variants: [Variant]
}

private struct Variant: Decodable {
    let wrong: String
}
