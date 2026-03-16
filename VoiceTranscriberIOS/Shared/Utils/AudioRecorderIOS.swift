import AVFoundation
import Foundation
import Combine

/// Handles audio recording on iOS using AVAudioEngine with real-time level monitoring.
/// Used by both the main app and the keyboard extension.
final class AudioRecorderIOS: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var audioLevels: [Float] = []
    @Published var recordingDuration: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var levelTimer: Timer?

    private let maxLevelHistory = 50

    // MARK: - Permissions

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var microphonePermissionGranted: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    // MARK: - Recording

    func startRecording() throws -> URL {
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            throw RecordingError.permissionDenied
        }

        // Configure audio session for recording
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(UUID().uuidString).m4a"
        let url = tempDir.appendingPathComponent(fileName)
        self.recordingURL = url

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecordingError.formatError
        }

        // Create output format: mono 16kHz for Whisper compatibility
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecordingError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: recordingFormat) else {
            throw RecordingError.converterError
        }

        // Create the output file
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let file = try AVAudioFile(forWriting: url, settings: outputSettings)
        self.audioFile = file

        // Tap the input node for audio data and level monitoring
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let level = self.calculateLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
                self.audioLevels.append(level)
                if self.audioLevels.count > self.maxLevelHistory {
                    self.audioLevels.removeFirst()
                }
            }

            // Convert and write to file
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * recordingFormat.sampleRate / inputFormat.sampleRate
            )
            guard frameCount > 0 else { return }
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil && convertedBuffer.frameLength > 0 {
                try? file.write(from: convertedBuffer)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.recordingStartTime = Date()

        // Start duration timer
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recordingStartTime else { return }
            DispatchQueue.main.async {
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        DispatchQueue.main.async {
            self.isRecording = true
            self.audioLevels = []
        }

        return url
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let engine = audioEngine, let url = recordingURL else { return nil }

        let duration = recordingDuration

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        levelTimer?.invalidate()
        levelTimer = nil
        audioEngine = nil
        audioFile = nil
        recordingStartTime = nil

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0
            self.recordingDuration = 0
        }

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard fileSize > 0 else {
            cleanupTempFile(url: url)
            return nil
        }

        return (url, duration)
    }

    func cancelRecording() {
        guard let engine = audioEngine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        levelTimer?.invalidate()
        levelTimer = nil
        audioEngine = nil
        audioFile = nil
        recordingURL = nil
        recordingStartTime = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0
            self.audioLevels = []
            self.recordingDuration = 0
        }
    }

    // MARK: - Level Calculation

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }

        let channelDataValue = channelData.pointee
        let channelDataArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }

        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

        let avgPower = 20 * log10(max(rms, 0.000001))
        let minDb: Float = -80
        let normalized = max(0, min(1, (avgPower - minDb) / (0 - minDb)))

        return normalized
    }

    // MARK: - Cleanup

    func cleanupTempFile(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Audio Level Monitor

final class AudioLevelMonitor: ObservableObject {
    @Published var smoothedLevel: Float = 0.0
    @Published var waveformBars: [Float] = Array(repeating: 0, count: 30)

    private var cancellables = Set<AnyCancellable>()
    private let smoothingFactor: Float = 0.3
    private let barCount = 30

    init(recorder: AudioRecorderIOS) {
        recorder.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                self.smoothedLevel = self.smoothedLevel * (1 - self.smoothingFactor) + level * self.smoothingFactor
                self.updateWaveformBars(level: self.smoothedLevel)
            }
            .store(in: &cancellables)
    }

    private func updateWaveformBars(level: Float) {
        waveformBars.removeFirst()
        waveformBars.append(level)
    }

    func reset() {
        smoothedLevel = 0
        waveformBars = Array(repeating: 0, count: barCount)
    }
}

// MARK: - Errors

enum RecordingError: LocalizedError {
    case formatError
    case converterError
    case permissionDenied
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format. Check your microphone."
        case .converterError: return "Failed to create audio converter."
        case .permissionDenied: return "Microphone access denied. Grant permission in Settings > Privacy & Security > Microphone."
        case .engineStartFailed: return "Failed to start audio engine."
        }
    }
}
