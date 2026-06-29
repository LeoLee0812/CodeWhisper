import AppKit
import Combine
import WhisperKit

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

    // MARK: - 流式转录（仅 .streaming 模式生效）

    /// 当前流式转录器（流式模式启动后非 nil）。
    private var streamer: AudioStreamTranscriber?
    /// 承载阻塞式 startStreamTranscription 的独立 Task。
    private var streamTask: Task<Void, Never>?
    /// 流式回调累积的最新全文（已确认 + 未确认段拼接）。
    private var latestStreamText = ""
    /// 停止请求标志：stopStreamingAndFinalize 置位，streamTask 创建完 streamer 后回检。
    /// 因为 WhisperKit 的 realtimeLoop 不检查 Task.isCancelled，cancel 无法停止流式，
    /// 唯一可靠的停止手段是调用 stopStreamTranscription()。此标志保证无论 streamer 何时就绪都能停掉。
    private var streamStopRequested = false
    /// 本次录音按下时锁定的模式：onPress 锁定、onRelease 按它分流，防中途切 Picker 走错 stop。
    private var activeRecordingMode: TranscriptionMode? = nil

    // MARK: - 初始化

    init() {
        self.settings = AppSettings.shared
        self.history = HistoryStore()

        // 注册热键：按模式分流。默认 .full 仍走原录音→转录路径，.streaming 走流式路径。
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            // 按下时锁定本次录音模式，后续松开按锁定模式分流，避免录音中切 Picker 走错 stop。
            let mode = self.settings.transcriptionMode
            self.activeRecordingMode = mode
            mode == .streaming ? self.startStreaming() : self.startRecording()
        }
        hotKey.onRelease = { [weak self] in
            guard let self else { return }
            // 用按下时锁定的模式收口；兜底取当前设置。用完即清。
            let mode = self.activeRecordingMode ?? self.settings.transcriptionMode
            self.activeRecordingMode = nil
            mode == .streaming ? self.stopStreamingAndFinalize() : self.stopRecordingAndTranscribe()
        }
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

    // MARK: - 流式转录（仅 .streaming 模式）

    /// 开始流式转录：自带麦克风采集，回调实时拼全文做预览。若正忙或下载中则忽略。
    func startStreaming() {
        guard !isBusy else { return }
        if case .downloadingModel = phase {
            CWLog.warn("模型下载中，暂不能录音")
            return
        }
        streamStopRequested = false
        phase = .recording
        latestStreamText = ""
        let language = settings.language

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 组装流式转录器；回调可能在任意线程，更新 @Published 时切回 @MainActor。
                let streamer = try await self.service.makeStreamTranscriber(language: language) { [weak self] _, newState in
                    guard let self else { return }
                    // 已确认 + 未确认段拼接为全文，再叠加 currentText 做实时预览。
                    let confirmed = newState.confirmedSegments.map { $0.text }.joined()
                    let unconfirmed = newState.unconfirmedSegments.map { $0.text }.joined()
                    let fullText = confirmed + unconfirmed
                    let preview = fullText + newState.currentText
                    let energy = newState.bufferEnergy.last ?? 0
                    Task { @MainActor in
                        self.latestStreamText = fullText
                        // 流式期间只做实时预览，不做繁简/术语后处理。
                        self.lastText = preview
                        self.audioLevel = energy
                    }
                }
                // 创建期间可能已请求停止（快速点按/短按）：必须在 MainActor 上回检 streamStopRequested。
                // 若已请求，立即停掉 streamer 且不进入永不退出的 realtimeLoop，避免麦克风永久占用。
                let shouldStop = await MainActor.run { () -> Bool in
                    if self.streamStopRequested { return true }
                    self.streamer = streamer
                    return false
                }
                if shouldStop {
                    await streamer.stopStreamTranscription()
                    return
                }
                // startStreamTranscription 会阻塞直到 stop，放在此独立 Task 内；其为 actor 方法自行跳转，不阻塞 MainActor。
                try await streamer.startStreamTranscription()
            } catch {
                CWLog.error("流式转录失败: \(error.localizedDescription)")
                await MainActor.run { self.phase = .error("流式转录失败: \(error.localizedDescription)") }
            }
        }
    }

    /// 停止流式转录并定稿：停采集后复用全量模式完全相同的后处理管线。
    func stopStreamingAndFinalize() {
        guard phase == .recording else { return }
        // 先置停止请求标志：即便此刻 streamer 尚未就绪，streamTask 创建完会回检此标志并立即停掉，
        // 不依赖对 realtimeLoop 无效的 cancel，杜绝麦克风永久占用。
        streamStopRequested = true
        phase = .transcribing
        audioLevel = 0

        let raw = latestStreamText
        let fixTerms = settings.fixTerms
        let outputMode = settings.outputMode
        let playSound = settings.playSound

        Task { [weak self] in
            guard let self else { return }
            // 停止 actor 上的流式采集，并清理 Task / streamer。
            // 若 streamer 已就绪则直接停；若仍为 nil，已置位的 streamStopRequested 会在 streamTask 内兜底停掉。
            if let streamer = self.streamer {
                await streamer.stopStreamTranscription()
            }
            // cancel 仅作清理，对 realtimeLoop 无效，不作为停止手段。
            self.streamTask?.cancel()
            self.streamTask = nil
            self.streamer = nil

            // 复用与 stopRecordingAndTranscribe 完全相同的后处理。
            var text = ChineseConverter.toSimplified(raw)
            text = ChineseConverter.normalizePunctuation(text)

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
        }
    }

    /// 切换录音：录音中则停止并转录，否则开始录音。
    func toggleRecording() {
        phase == .recording ? stopRecordingAndTranscribe() : startRecording()
    }
}
