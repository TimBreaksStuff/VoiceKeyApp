import AVFoundation

/// Taps the mic at its native format, converts to 16kHz mono Float32,
/// and auto-stops after ~1s of trailing silence (only once speech was heard).
final class AudioRecorder {
    enum RecError: Error { case noMicFormat }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var heardSpeech = false
    private var silentSampleCount = 0
    private var autoStopFired = false
    var onAutoStop: (() -> Void)? // fired once per recording, on main queue

    private static let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: 16_000, channels: 1,
                                                 interleaved: false)!
    private let speechRMS: Float = 0.015
    private let silenceSamplesNeeded = 16_000 // 1s @ 16kHz

    func start() throws {
        lock.lock()
        samples.removeAll()
        heardSpeech = false
        silentSampleCount = 0
        autoStopFired = false
        lock.unlock()

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0) // native rate, e.g. 48kHz
        Log.line("mic input format \(inFormat.sampleRate)Hz \(inFormat.channelCount)ch")
        // reports 0 Hz before mic permission is granted
        guard inFormat.sampleRate > 0 else { throw RecError.noMicFormat }
        converter = AVAudioConverter(from: inFormat, to: Self.outFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self, let conv = self.converter else { return }
            let ratio = 16_000 / inFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: Self.outFormat, frameCapacity: cap) else { return }
            var fed = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                // must return .noDataNow after feeding once, or convert() spins forever
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            let n = Int(out.frameLength)
            guard n > 0, let ch = out.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: ch, count: n))
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(n))

            self.lock.lock()
            self.samples.append(contentsOf: chunk)
            if rms >= self.speechRMS {
                self.heardSpeech = true
                self.silentSampleCount = 0
            } else if self.heardSpeech {
                self.silentSampleCount += n
            }
            let shouldStop = self.heardSpeech
                && self.silentSampleCount >= self.silenceSamplesNeeded
                && !self.autoStopFired
            if shouldStop { self.autoStopFired = true }
            self.lock.unlock()
            if shouldStop { DispatchQueue.main.async { self.onAutoStop?() } }
        }
        engine.prepare()
        try engine.start()
    }

    /// Returns (samples, heardSpeech). Skip whisper entirely when heardSpeech
    /// is false — it hallucinates ("Thank you.") on silence.
    func stop() -> ([Float], Bool) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        defer { lock.unlock() }
        return (samples, heardSpeech)
    }
}
