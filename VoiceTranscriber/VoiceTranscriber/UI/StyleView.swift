import SwiftUI

/// Style configuration view with per-context tone selection.
struct StyleView: View {
    @ObservedObject var config: ConfigManager
    @State private var selectedContext: StyleContext = .personalMessages

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Style")
                    .font(.system(size: 26, weight: .bold))

                // Context tabs
                HStack(spacing: 20) {
                    ForEach(StyleContext.allCases) { context in
                        Button(action: { selectedContext = context }) {
                            Text(context.displayName)
                                .font(.system(size: 13, weight: selectedContext == context ? .semibold : .regular))
                                .foregroundColor(selectedContext == context ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if selectedContext == context {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: 6)
                            }
                        }
                    }
                    Spacer()
                }

                // Context info card
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Style for \(selectedContext.displayName.lowercased())")
                            .font(.system(size: 15, weight: .semibold))

                        Text(selectedContext.description)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(appIcons(for: selectedContext), id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                // Style cards
                let currentTone = config.styleTone(for: selectedContext)

                HStack(spacing: 16) {
                    ForEach(StyleTone.allCases) { tone in
                        StyleCard(
                            tone: tone,
                            isSelected: currentTone == tone,
                            action: {
                                config.setStyleTone(tone, for: selectedContext)
                            }
                        )
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func appIcons(for context: StyleContext) -> [String] {
        switch context {
        case .personalMessages: return ["message.fill", "phone.fill", "bubble.left.fill"]
        case .workMessages: return ["bubble.left.and.bubble.right.fill", "video.fill"]
        case .email: return ["envelope.fill", "paperplane.fill"]
        case .other: return ["doc.text.fill", "chevron.left.forwardslash.chevron.right", "note.text"]
        }
    }
}

// MARK: - Style Card

private struct StyleCard: View {
    let tone: StyleTone
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Title
                Text(tone.displayName)
                    .font(.system(size: 22, weight: .bold, design: tone == .veryCasual ? .default : .serif))
                    .foregroundColor(.primary)

                // Subtitle
                Text(tone.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                // Example
                Text(tone.example)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 6 : 2, y: isSelected ? 3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
