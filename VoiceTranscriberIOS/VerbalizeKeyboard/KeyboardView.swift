import SwiftUI

struct KeyboardView: View {
    @ObservedObject var state: KeyboardState

    let onKeyTap: (String) -> Void
    let onMicTap: () -> Void
    let onBackspace: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onGlobe: () -> Void
    let onShift: () -> Void

    // Standard QWERTY layout
    private let row1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let row2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private let row3 = ["z", "x", "c", "v", "b", "n", "m"]

    // Number layout
    private let numRow1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let numRow2 = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
    private let numRow3 = [".", ",", "?", "!", "'"]

    // Symbol layout
    private let symRow1 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
    private let symRow2 = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
    private let symRow3 = [".", ",", "?", "!", "'"]

    @Environment(\.colorScheme) private var colorScheme

    private var keyBg: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.white
    }

    private var specialKeyBg: Color {
        colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(.systemGray3)
    }

    private var bgColor: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(.systemGray5)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar (shown during recording/processing)
            if state.showStatus {
                statusBar
            }

            // Key rows
            VStack(spacing: 8) {
                if state.showNumbers {
                    numberLayout
                } else if state.showSymbols {
                    symbolLayout
                } else {
                    letterLayout
                }

                // Bottom row: globe, mic, space, return
                bottomRow
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
        }
        .background(bgColor)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if state.isRecording {
                // Waveform
                HStack(spacing: 1.5) {
                    ForEach(Array(displayLevels.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.red)
                            .frame(width: 2, height: max(2, CGFloat(level) * 20))
                    }
                }
                .frame(height: 20)

                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            } else if state.isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text(state.statusMessage)
                .font(.caption)
                .foregroundColor(state.isRecording ? .red : .secondary)
                .lineLimit(1)

            Spacer()

            if state.isRecording {
                Button {
                    onMicTap()
                } label: {
                    Text("Done")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(state.isRecording ? Color.red.opacity(0.05) : Color.clear)
    }

    private var displayLevels: [Float] {
        let count = 20
        if state.audioLevels.count >= count {
            return Array(state.audioLevels.suffix(count))
        }
        return Array(repeating: Float(0), count: count - state.audioLevels.count) + state.audioLevels
    }

    // MARK: - Letter Layout

    private var letterLayout: some View {
        VStack(spacing: 8) {
            // Row 1
            HStack(spacing: 4) {
                ForEach(row1, id: \.self) { key in
                    KeyButton(label: displayKey(key), style: .regular, bgColor: keyBg) {
                        onKeyTap(key)
                    }
                }
            }

            // Row 2
            HStack(spacing: 4) {
                ForEach(row2, id: \.self) { key in
                    KeyButton(label: displayKey(key), style: .regular, bgColor: keyBg) {
                        onKeyTap(key)
                    }
                }
            }

            // Row 3 with shift and backspace
            HStack(spacing: 4) {
                // Shift
                KeyButton(
                    label: state.isCapsLocked ? "⇪" : "⇧",
                    style: .wide,
                    bgColor: (state.isShifted || state.isCapsLocked) ? Color.white : specialKeyBg,
                    foreground: (state.isShifted || state.isCapsLocked) ? .black : nil
                ) {
                    onShift()
                }

                ForEach(row3, id: \.self) { key in
                    KeyButton(label: displayKey(key), style: .regular, bgColor: keyBg) {
                        onKeyTap(key)
                    }
                }

                // Backspace
                KeyButton(label: "⌫", style: .wide, bgColor: specialKeyBg) {
                    onBackspace()
                }
            }
        }
    }

    // MARK: - Number Layout

    private var numberLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(numRow1, id: \.self) { key in
                    KeyButton(label: key, style: .regular, bgColor: keyBg) { onKeyTap(key) }
                }
            }

            HStack(spacing: 4) {
                ForEach(numRow2, id: \.self) { key in
                    KeyButton(label: key, style: .regular, bgColor: keyBg) { onKeyTap(key) }
                }
            }

            HStack(spacing: 4) {
                KeyButton(label: "#+=", style: .wide, bgColor: specialKeyBg) {
                    state.showNumbers = false
                    state.showSymbols = true
                }

                ForEach(numRow3, id: \.self) { key in
                    KeyButton(label: key, style: .regular, bgColor: keyBg) { onKeyTap(key) }
                }

                KeyButton(label: "⌫", style: .wide, bgColor: specialKeyBg) { onBackspace() }
            }
        }
    }

    // MARK: - Symbol Layout

    private var symbolLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(symRow1, id: \.self) { key in
                    KeyButton(label: key, style: .regular, bgColor: keyBg) { onKeyTap(key) }
                }
            }

            HStack(spacing: 4) {
                ForEach(symRow2, id: \.self) { key in
                    KeyButton(label: key, style: .regular, bgColor: keyBg) { onKeyTap(key) }
                }
            }

            HStack(spacing: 4) {
                KeyButton(label: "123", style: .wide, bgColor: specialKeyBg) {
                    state.showSymbols = false
                    state.showNumbers = true
                }

                ForEach(symRow3, id: \.self) { key in
                    KeyButton(label: key, style: .regular, bgColor: keyBg) { onKeyTap(key) }
                }

                KeyButton(label: "⌫", style: .wide, bgColor: specialKeyBg) { onBackspace() }
            }
        }
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 4) {
            // Number/ABC toggle
            KeyButton(
                label: (state.showNumbers || state.showSymbols) ? "ABC" : "123",
                style: .medium,
                bgColor: specialKeyBg
            ) {
                if state.showNumbers || state.showSymbols {
                    state.showNumbers = false
                    state.showSymbols = false
                } else {
                    state.showNumbers = true
                }
            }

            // Globe (switch keyboard)
            KeyButton(label: "🌐", style: .small, bgColor: specialKeyBg) {
                onGlobe()
            }

            // Microphone button
            micButton

            // Space bar
            KeyButton(label: "space", style: .space, bgColor: keyBg) {
                onSpace()
            }

            // Return
            KeyButton(label: "return", style: .medium, bgColor: specialKeyBg) {
                onReturn()
            }
        }
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button {
            onMicTap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(micButtonColor)
                    .frame(width: 44, height: 42)

                if state.isRecording {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                } else if state.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(state.isProcessing)
    }

    private var micButtonColor: Color {
        if state.isRecording { return .red }
        if state.isProcessing { return .orange }
        return .blue
    }

    // MARK: - Helpers

    private func displayKey(_ key: String) -> String {
        (state.isShifted || state.isCapsLocked) ? key.uppercased() : key
    }
}

// MARK: - Key Button

enum KeyStyle {
    case regular
    case wide
    case medium
    case small
    case space
}

struct KeyButton: View {
    let label: String
    let style: KeyStyle
    let bgColor: Color
    var foreground: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(fontSize)
                .foregroundColor(foreground ?? .primary)
                .frame(maxWidth: maxWidth, minHeight: 42)
                .background(bgColor)
                .cornerRadius(5)
                .shadow(color: .black.opacity(0.15), radius: 0.5, x: 0, y: 1)
        }
    }

    private var fontSize: Font {
        switch style {
        case .regular: return .system(size: 22)
        case .wide, .medium: return .system(size: 14, weight: .medium)
        case .small: return .system(size: 16)
        case .space: return .system(size: 14)
        }
    }

    private var maxWidth: CGFloat {
        switch style {
        case .regular: return .infinity
        case .wide: return 50
        case .medium: return 70
        case .small: return 36
        case .space: return .infinity
        }
    }
}
