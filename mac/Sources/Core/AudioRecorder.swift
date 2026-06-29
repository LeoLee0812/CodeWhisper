import AVFoundation
import Combine

/// 麦克风录音器：采集音频并转换为 WhisperKit 需要的 16kHz 单声道 Float 采样。
@MainActor
final class AudioRecorder: ObservableObject {
    /// 实时输入电平（0...1），用于 UI 波形/动画。
    @Published var level: Float = 0

    private let engine = AVAudioEngine()
    // converter 仅在 start() 安装 tap 前写入、在 nonisolated 的 process 中读取，
    // 时序上不存在并发读写，故标记为 nonisolated(unsafe)。
    private nonisolated(unsafe) var converter: AVAudioConverter?
    // 常量，nonisolated 后可在音频 tap 回调中安全读取。
    private nonisolated let targetSampleRate: Double = 16000

    /// 累积的 16kHz 单声道采样。
    /// 由 bufferLock 保护，故标记为 nonisolated(unsafe) 以便在 tap 回调中追加。
    private nonisolated(unsafe) var samples: [Float] = []
    private nonisolated let bufferLock = NSLock()
    private(set) var isRecording = false

    /// 目标格式：16kHz 单声道 Float32（不可变常量，可跨线程读取）。
    private nonisolated let targetFormat: AVAudioFormat =
        AVAudioFormat(commonFormat: .pcmFormatFloat32,
                      sampleRate: 16000,
                      channels: 1,
                      interleaved: false)!

    /// 开始录音。返回是否成功。
    @discardableResult
    func start() -> Bool {
        guard !isRecording else { return true }

        bufferLock.lock(); samples.removeAll(); bufferLock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            CWLog.error("无法获取麦克风输入格式")
            return false
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRecording = true
            CWLog.info("开始录音")
            return true
        } catch {
            CWLog.error("录音启动失败: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            return false
        }
    }

    /// 停止录音，返回采集到的 16kHz 单声道采样。
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        bufferLock.lock(); let result = samples; bufferLock.unlock()
        CWLog.info("录音结束，采样数 \(result.count)（约 \(String(format: "%.1f", Double(result.count) / targetSampleRate)) 秒）")
        return result
    }

    // MARK: - 音频处理

    private nonisolated func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }

        let ratio = targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var fed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if let error = error {
            CWLog.error("音频转换失败: \(error.localizedDescription)")
            return
        }

        guard let channel = outBuffer.floatChannelData?[0] else { return }
        let frames = Int(outBuffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: frames))

        // 计算 RMS 电平用于 UI
        var sum: Float = 0
        for v in chunk { sum += v * v }
        let rms = frames > 0 ? (sum / Float(frames)).squareRoot() : 0

        bufferLock.lock()
        samples.append(contentsOf: chunk)
        bufferLock.unlock()

        Task { @MainActor [weak self] in
            self?.level = min(1, rms * 8)
        }
    }
}
