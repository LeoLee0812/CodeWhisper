import Foundation
import WhisperKit

/// WhisperKit 推理封装：负责模型下载/加载与音频转录。
/// 运行在 actor 上以保证并发安全；转录在后台执行，不阻塞主线程。
/// 对应 Python 版 transcriber.Transcriber 的推理与幻觉过滤部分。
actor TranscriptionService {

    /// 已加载的 WhisperKit 推理管线（未加载时为 nil）。
    private var pipe: WhisperKit?

    /// 当前已加载的模型名，用于避免重复加载同一模型。
    private var currentModelName: String?

    /// 是否已加载模型。
    var isLoaded: Bool { pipe != nil }

    /// 当前已加载的模型名。
    var loadedModelName: String? { currentModelName }

    /// 转录服务可能抛出的错误。
    enum ServiceError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "模型尚未加载"
            }
        }
    }

    // MARK: - 模型加载

    /// 下载并加载指定模型。已加载同名模型则直接跳过。
    /// - Parameters:
    ///   - name: WhisperKit 模型名（如 openai_whisper-large-v3-v20240930_turbo）。
    ///   - onProgress: 下载进度回调（0...1），可能在任意线程触发，调用方需自行切回主线程。
    func loadModel(name: String, onProgress: @escaping (Double) -> Void) async throws {
        // 已加载同名模型则无需重复加载。
        if pipe != nil, currentModelName == name { return }

        // Apple Silicon 优化：Mel 用 CPU+GPU，编码器/解码器走 ANE。
        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )

        let modelFolder: String
        // 内置离线模型专用的本地 tokenizer 目录（纯离线，避免首启联网拉 tokenizer）。
        // 仅内置模型分支会赋值；下载分支保持 nil，让 WhisperKit 自行联网取 tokenizer。
        var tokenizerFolder: URL? = nil

        // 一级：随包内置模型目录（纯离线，开箱即用，无需联网）。
        if let bundled = Self.bundledModelFolder(for: name) {
            CWLog.info("使用随包内置模型: \(name)")
            modelFolder = bundled
            tokenizerFolder = Self.bundledTokenizerFolder()
            onProgress(1.0)
        } else {
            // 二/三级：缓存目录已下载则复用，否则联网下载（进度可控）。
            let base = AppPaths.modelsDirectory()
            CWLog.info("开始下载/加载模型: \(name)")
            let folder = try await WhisperKit.download(
                variant: name,
                downloadBase: base,
                from: "argmaxinc/whisperkit-coreml"
            ) { progress in
                onProgress(progress.fractionCompleted)
            }
            modelFolder = folder.path
        }

        // 用本地目录初始化管线，关闭再次下载。
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            tokenizerFolder: tokenizerFolder,
            computeOptions: computeOptions,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        self.pipe = try await WhisperKit(config)
        self.currentModelName = name
        CWLog.info("模型加载完成: \(name)")
    }

    /// 查找随包内置模型目录：`<Bundle>/Models/<variant>`。
    /// 仅当其下三个核心 mlmodelc 都存在时返回该路径，否则返回 nil（回退到下载）。
    private static func bundledModelFolder(for variant: String) -> String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let folder = (resourcePath as NSString)
            .appendingPathComponent("Models/\(variant)")
        let fm = FileManager.default
        let required = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
        for component in required {
            let path = (folder as NSString).appendingPathComponent(component)
            if !fm.fileExists(atPath: path) { return nil }
        }
        return folder
    }

    /// 查找随包内置 tokenizer 目录：`<Bundle>/Models/tokenizer`。
    /// 仅当该目录存在且含 `tokenizer.json` 时返回，否则返回 nil（回退到 WhisperKit 联网取 tokenizer）。
    private static func bundledTokenizerFolder() -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let folder = (resourcePath as NSString)
            .appendingPathComponent("Models/tokenizer")
        let tokenizerJSON = (folder as NSString).appendingPathComponent("tokenizer.json")
        guard FileManager.default.fileExists(atPath: tokenizerJSON) else { return nil }
        return URL(fileURLWithPath: folder, isDirectory: true)
    }

    // MARK: - 转录

    /// 转录 16kHz 单声道 Float 采样，返回最终文本（已过滤幻觉、已 trim）。
    /// - Parameters:
    ///   - samples: 16kHz 单声道 Float 采样。
    ///   - language: 语言代码（zh / en / ...）；传 "auto" 时自动检测语言。
    ///   - termHint: 可选术语提示（如词典中的高频术语拼接），编码为 promptTokens 注入解码器，
    ///               提升专业术语识别准确率。仅在非 auto 且 tokenizer 可用时生效。
    func transcribe(_ samples: [Float], language: String, termHint: String? = nil) async throws -> String {
        guard let pipe = pipe else { throw ServiceError.modelNotLoaded }
        guard !samples.isEmpty else { return "" }

        // auto 时让 WhisperKit 自动检测语言，否则锁定指定语言。
        var options: DecodingOptions
        if language == "auto" {
            options = DecodingOptions(task: .transcribe, language: nil, temperature: 0.0,
                                      detectLanguage: true,
                                      compressionRatioThreshold: 2.4, noSpeechThreshold: 0.6)
        } else {
            options = DecodingOptions(task: .transcribe, language: language, temperature: 0.0,
                                      usePrefillPrompt: true,
                                      compressionRatioThreshold: 2.4, noSpeechThreshold: 0.6)

            // 术语提示：编码为 promptTokens 注入，过滤掉特殊 token。
            if let hint = termHint?.trimmingCharacters(in: .whitespacesAndNewlines),
               !hint.isEmpty,
               let tok = pipe.tokenizer {
                let promptTokens = tok.encode(text: " " + hint)
                    .filter { $0 < tok.specialTokens.specialTokenBegin }
                if !promptTokens.isEmpty {
                    options.promptTokens = promptTokens
                    options.usePrefillPrompt = true
                }
            }
        }

        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map { $0.text }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 幻觉过滤：循环重复通常出现在静音/低质量音频，视为无效输出。
        if Self.looksLikeRepetitionLoop(text) {
            CWLog.warn("检测到循环重复幻觉，丢弃该次转录结果")
            return ""
        }
        return text
    }

    // MARK: - 幻觉过滤

    /// 检测明显的「循环重复」幻觉（常见于静音/低质量音频）。
    /// 移植自 Python 版 transcriber._looks_like_repetition_loop。
    /// 命中任一条件即认为是循环重复：连续相同词 run ≥ maxRepeat、单字符重复、短语重复。
    static func looksLikeRepetitionLoop(_ text: String, maxRepeat: Int = 10) -> Bool {
        guard !text.isEmpty else { return false }

        // 归一化空白：连续空白压缩为单个空格并去首尾空白。
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return false }

        // 1) 按空格分词：检测连续相同词的超长 run（更适用于英文/夹杂英文）。
        let words = normalized.split(separator: " ").map(String.init)
        if words.count >= maxRepeat {
            var run = 1
            for idx in 1..<words.count {
                if words[idx] == words[idx - 1] {
                    run += 1
                    if run >= maxRepeat { return true }
                } else {
                    run = 1
                }
            }
        }

        // 2) 中文常无空格输出：去除标点/空白后做字符与短语重复检测。
        let compact = normalized.replacingOccurrences(
            of: "[\\s，。！？,.!?:;；、】【\\[\\]()（）\"'“”‘’—…·]+",
            with: "",
            options: .regularExpression
        )
        guard compact.count >= maxRepeat else { return false }

        // 2.1) 单字符重复（如「啊啊啊啊...」）。
        if compact.range(of: "(.)\\1{\(maxRepeat - 1),}", options: .regularExpression) != nil {
            return true
        }

        // 2.2) 短语重复（如「谢谢观看谢谢观看...」），尝试 2~10 字符片段。
        for unitLen in 2...10 {
            if compact.count < unitLen * maxRepeat { continue }
            let pattern = "(.{\(unitLen)})\\1{\(maxRepeat - 1),}"
            if compact.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}
