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

                // Context banner
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.linearGradient(
                            colors: bannerColors(for: selectedContext),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This style applies in \(selectedContext.displayName.lowercased())")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text(selectedContext.description)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(20)

                        Spacer()

                        // App icons placeholder
                        HStack(spacing: -4) {
                            ForEach(appIcons(for: selectedContext), id: \.self) { icon in
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: icon)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.7))
                                    )
                            }
                        }
                        .padding(.trailing, 20)
                    }
                }
                .frame(height: 100)

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

    private func bannerColors(for context: StyleContext) -> [Color] {
        switch context {
        case .personalMessages: return [.blue.opacity(0.7), .cyan.opacity(0.5)]
        case .workMessages: return [.purple.opacity(0.7), .indigo.opacity(0.5)]
        case .email: return [.orange.opacity(0.7), .red.opacity(0.5)]
        case .other: return [.gray.opacity(0.5), .brown.opacity(0.4)]
        }
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
