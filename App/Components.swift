import SwiftUI

// MARK: - Safety badge pill
struct SafetyBadge: View {
    var level: SafetyLevel
    var vocab: SafetyVocab
    var size: BadgeSize = .md

    enum BadgeSize { case sm, md }

    var body: some View {
        let b = vocab.badge(level)
        Text(b.tag)
            .font(.system(size: size == .sm ? 11 : 12, weight: .semibold))
            .padding(.vertical, size == .sm ? 3 : 5)
            .padding(.horizontal, size == .sm ? 8 : 10)
            .foregroundStyle(b.color)
            .background(b.tint, in: Capsule())
    }
}

// MARK: - Primary button
struct CaminosButton: View {
    enum Variant { case primary, secondary, ghost, accent }

    var label: String
    var icon: String? = nil
    var variant: Variant = .primary
    var action: () -> Void

    @State private var pressed = false

    var bg: Color {
        switch variant {
        case .primary:   T.ink
        case .secondary: Color.black.opacity(0.06)
        case .ghost:     Color.clear
        case .accent:    T.accent
        }
    }
    var fg: Color {
        switch variant {
        case .primary, .accent: T.cream
        case .secondary, .ghost: T.textPrimary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .medium)) }
                Text(label).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(fg)
            .background(bg, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                if variant == .ghost {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.14), lineWidth: 1)
                }
            }
            .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 99,
            pressing: { isPressing in
                withAnimation(.easeInOut(duration: 0.12)) { pressed = isPressing }
            }, perform: {})
    }
}

// MARK: - Small circular back button
struct BackButton: View {
    var night: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(T.pri(night))
                .frame(width: 38, height: 38)
                .background(T.surface(night), in: Circle())
                .caminosCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transit mode chip
struct TransitChip: View {
    var mode: TransitMode
    var night: Bool

    var body: some View {
        Image(systemName: mode.sfSymbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(T.pri(night))
            .frame(width: 26, height: 26)
            .background(night ? Color.white.opacity(0.06) : Color.black.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Screen header row (back + title + optional trailing)
struct ScreenHeader: View {
    var supertitle: String
    var title: String
    var night: Bool
    var onBack: () -> Void
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            BackButton(night: night, action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(supertitle.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(T.sec(night))
                    .tracking(0.4)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(T.pri(night))
            }
            Spacer()
            if let t = trailing { t }
        }
    }
}

// MARK: - Route leg arrow divider
struct LegArrow: View {
    var night: Bool
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(T.sec(night))
    }
}
