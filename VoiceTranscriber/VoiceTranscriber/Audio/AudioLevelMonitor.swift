import Foundation
import Combine

/// Processes raw audio levels into smoothed values suitable for waveform visualization.
final class AudioLevelMonitor: ObservableObject {
    @Published var smoothedLevel: Float = 0.0
    @Published var waveformBars: [Float] = Array(repeating: 0, count: 30)

    private var cancellables = Set<AnyCancellable>()
    private let smoothingFactor: Float = 0.3
    private let barCount = 30

    init(recorder: AudioRecorder) {
        // Smooth the audio level for UI display
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
        // Shift bars left and add new value
        waveformBars.removeFirst()
        waveformBars.append(level)
    }

    func reset() {
        smoothedLevel = 0
        waveformBars = Array(repeating: 0, count: barCount)
    }
}
