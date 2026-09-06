import SwiftUI

/// The app's view on all four chips: when to play each, or why to sit on it.
struct ChipPlanCard: View {
    let plan: [ChipAdvice]
    @State private var expanded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Chips", systemImage: "sparkles.rectangle.stack")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                if playable > 0 {
                    Text("\(playable) to play now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.deepPurple)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accentGradient))
                }
            }

            ForEach(plan) { advice in
                row(advice)
                if advice.id != plan.last?.id {
                    Divider().overlay(.white.opacity(0.12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var playable: Int { plan.filter { $0.verdict.isPlay }.count }

    private func row(_ advice: ChipAdvice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expanded = expanded == advice.id ? nil : advice.id
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: advice.chip.icon)
                        .font(.subheadline)
                        .foregroundStyle(tint(advice))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(advice.chip.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(advice.headline)
                            .font(.caption)
                            .foregroundStyle(tint(advice))
                    }
                    Spacer(minLength: 0)

                    if advice.verdict.isPlay {
                        Text(advice.chip == .wildcard
                             ? String(format: "+%.0f%%", advice.gain)
                             : String(format: "+%.0f pts", advice.gain))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.deepPurple)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.accentGradient))
                    }
                    Image(systemName: expanded == advice.id ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                // Without an explicit shape the row's empty space isn't
                // hittable, so most of a tap on it does nothing.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded == advice.id {
                VStack(alignment: .leading, spacing: 8) {
                    Text(advice.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(advice.chip.idealCondition)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)

                    if advice.ranked.count > 1 {
                        HStack(spacing: 6) {
                            Text("Best weeks")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                            ForEach(advice.ranked.prefix(3), id: \.gameweek) { entry in
                                Text(String(format: "GW%d · %.0f", entry.gameweek, entry.gain))
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Capsule().fill(.white.opacity(0.1)))
                            }
                        }
                    }
                }
                .padding(.leading, 36)
                .padding(.bottom, 2)
            }
        }
    }

    private func tint(_ advice: ChipAdvice) -> Color {
        switch advice.verdict {
        case .play: return Theme.mint
        case .hold: return .white.opacity(0.55)
        case .used, .expired: return .white.opacity(0.35)
        }
    }
}

/// Asks which chips have already been played, when the user is telling the app
/// about a squad they already own.
struct ChipsUsedCard: View {
    @Binding var usage: ChipUsage
    let currentGameweek: Int

    private var secondHalf: Bool { currentGameweek >= 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chips you've already played")
                .font(.headline).foregroundStyle(.white)
            Text(secondHalf
                 ? "You're in the second half of the season, so these are your second set. Tap any you've used since gameweek 20."
                 : "Tap any you've already used this season. I won't suggest one you no longer have.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(Chip.allCases) { chip in
                    let used = usage.hasUsed(chip, secondHalf: secondHalf)
                    Button {
                        usage.toggle(chip, secondHalf: secondHalf)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: used ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                            Text(chip.name)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(used ? Theme.deepPurple : .white)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(
                            Capsule().fill(used ? AnyShapeStyle(Theme.accentGradient)
                                                : AnyShapeStyle(Color.white.opacity(0.12)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if usage.count > 0 {
                Text("\(usage.count) played · \(Chip.allCases.count - usage.count) still available")
                    .font(.caption2)
                    .foregroundStyle(Theme.mint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
