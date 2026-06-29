import AppKit
import Combine

/// 应用唯一协调器：串起录音 → 转录 → 繁简/标点 → 术语纠正 → 上屏 → 历史。
/// UI 只读它的 @Published 状态，所有状态都在主线程隔离；耗时的转录在后台 Task / actor 内执行。
@MainActor
final class AppState: ObservableObject {

    /// 应用运行阶段。
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case downloadingModel(Double)   // 进度 0...1
        case ready
        case error(String)
    }

    @Published var phase: Phase = .idle
    @Published var lastText: String = ""
    /// 录音时实时电平（0...1），代理自 recorder.level，供 UI 绘制。
    @Published var audioLevel: Float = 0

    let history: HistoryStore
    let settings: AppSettings

    /// 是否正忙（录音或转录中）。
    var isBusy: Bool { phase == .recording || phase == .transcribing }

    // MARK: - 依赖

    private let recorder = AudioRecorder()
    private let service = TranscriptionService()
    private let hotKey = HotKeyManager()
    private let dictionary = DictionaryManager()
    private var cancellables = Set<AnyCancellable>()

    /// 模型加载幂等守卫：加载进行中时重入直接 return，避免并发重复加载。
    private var isPreparingModel = false

    // MARK: - 初始化

    init() {
        self.settings = AppSettings.shared
        self.history = HistoryStore()

        // 注册热键：按下开始录音、松开停止并转录。
        hotKey.onPress = { [weak self] in self?.startRecording() }
        hotKey.onRelease = { [weak self] in self?.stopRecordingAndTranscribe() }
        hotKey.register(keyCode: settings.hotKeyCode, carbonModifiers: settings.hotKeyModifiers)

        // 代理录音电平到 UI 状态。
        recorder.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] level in self?.audioLevel = level }
            .store(in: &cancellables)

        // 热键设置变化时重新注册。
        settings.$hotKeyCode
            .combineLatest(settings.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] code, mods in
                self?.hotKey.register(keyCode: code, carbonModifiers: mods)
            }
            .store(in: &cancellables)

        // 开机自启设置变化时同步系统注册。
        settings.$launchAtLogin
            .dropFirst()
            .sink { enabled in LaunchAtLoginManager.apply(enabled) }
            .store(in: &cancellables)

        // App 启动即在后台预加载模型，避免用户先按热键时模型未就绪。
        // prepareModel() 幂等且 busy 时不抢 phase，与后续 MenuContentView.task 调用互不冲突。
        Task { [weak self] in await self?.prepareModel() }
    }

    // MARK: - 模型

    /// 下载/加载模型，期间更新 phase（.downloadingModel → .ready / .error）。
    /// 该方法被 MenuContentView.task 反复调用，因此必须幂等且绝不抢占录音/转录状态。
    func prepareModel() async {
        // 幂等：加载进行中时重入直接返回，防止并发重复加载。
        guard !isPreparingModel else { return }

        // 不抢录音/转录状态：正忙时绝不改写 phase，加载留到空闲时再做。
        guard !isBusy else { return }

        // 已加载则不重复加载；仅在空闲 idle 时补置为 ready，否则不动 phase。
        if await service.isLoaded {
            if case .idle = phase { phase = .ready }
            return
        }

        isPreparingModel = true
        defer { isPreparingModel = false }

        phase = .downloadingModel(0)
        let name = settings.modelName
        do {
            try await service.loadModel(name: name) { [weak self] progress in
                Task { @MainActor in self?.phase = .downloadingModel(progress) }
            }
            // 仅在仍空闲时置 ready，避免加载期间用户已开始录音被冲掉。
            if !isBusy { phase = .ready }
        } catch {
            CWLog.error("模型加载失败: \(error.localizedDescription)")
            phase = .error("模型加载失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 录音 / 转录

    /// 开始录音。若正忙或正在下载模型则忽略。
    func startRecording() {
        guard !isBusy else { return }
        if case .downloadingModel = phase {
            CWLog.warn("模型下载中，暂不能录音")
            return
        }
        guard recorder.start() else {
            phase = .error("无法启动录音，请检查麦克风权限")
            return
        }
        phase = .recording
    }

    /// 停止录音并转录，完整跑通后处理管线后上屏并写入历史。
    func stopRecordingAndTranscribe() {
        guard phase == .recording else { return }
        let samples = recorder.stop()
        audioLevel = 0
        phase = .transcribing

        let language = settings.language
        let fixTerms = settings.fixTerms
        let outputMode = settings.outputMode
        let playSound = settings.playSound

        Task { [weak self] in
            guard let self else { return }
            do {
                // 后台转录。
                let raw = try await self.service.transcribe(samples, language: language)

                // 繁简转换 + 标点规范化。
                var text = ChineseConverter.toSimplified(raw)
                text = ChineseConverter.normalizePunctuation(text)

                // 术语纠正。
                if fixTerms {
                    text = self.dictionary.fix(text).text
                }

                let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !final.isEmpty else {
                    self.phase = .ready
                    return
                }

                // 上屏。
                switch outputMode {
                case .copyOnly: ClipboardManager.copy(final)
                case .copyAndPaste: ClipboardManager.copyAndPaste(final)
                }

                self.history.add(final)
                self.lastText = final

                if playSound {
                    if let sound = NSSound(named: "Glass") { sound.play() } else { NSSound.beep() }
                }
                self.phase = .ready
            } catch {
                CWLog.error("转录失败: \(error.localizedDescription)")
                self.phase = .error("转录失败: \(error.localizedDescription)")
            }
        }
    }

    /// 切换录音：录音中则停止并转录，否则开始录音。
    func toggleRecording() {
        phase == .recording ? stopRecordingAndTranscribe() : startRecording()
    }
}
