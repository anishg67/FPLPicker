import SwiftUI

/// The game's own fixture-difficulty palette: 1 and 2 are kind, 3 is neutral,
/// 4 and 5 are hard. A blank gameweek is drawn darker than the worst fixture,
/// because no match at all is worse than a hard one.
enum FixtureTint {
    static func colour(_ difficulty: Double, isBlank: Bool) -> Color {
        if isBlank { return Color(red: 0.16, green: 0.16, blue: 0.20) }
        switch difficulty {
        case ..<2.0: return Color(red: 0.00, green: 0.68, blue: 0.42)
        case ..<2.75: return Color(red: 0.42, green: 0.78, blue: 0.35)
        case ..<3.25: return Color(red: 0.42, green: 0.42, blue: 0.50)
        case ..<4.25: return Color(red: 0.89, green: 0.42, blue: 0.24)
        default: return Color(red: 0.84, green: 0.18, blue: 0.26)
        }
    }

    static func label(_ difficulty: Double) -> String {
        switch difficulty {
        case ..<2.0: return "Very kind"
        case ..<2.75: return "Kind"
        case ..<3.25: return "Even"
        case ..<4.25: return "Hard"
        default: return "Very hard"
        }
    }
}

/// One gameweek's cell in a ticker.
struct FixtureCell: View {
    let week: GameweekFixtures
    var compact = false

    var body: some View {
        VStack(spacing: 1) {
            if week.isBlank {
                Text("—")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(week.fixtures) { fixture in
                    Text(fixture.ticker)
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 26 : 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FixtureTint.colour(week.difficulty, isBlank: week.isBlank))
        )
        .accessibilityLabel(week.isBlank
            ? "Gameweek \(week.gameweek): no fixture"
            : "Gameweek \(week.gameweek): \(week.fixtures.map(\.label).joined(separator: ", "))")
    }
}

/// A club's next few gameweeks, as a row of coloured cells.
struct FixtureRun: View {
    let weeks: [GameweekFixtures]
    var compact = false
    var showsGameweekNumbers = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weeks) { week in
                VStack(spacing: 2) {
                    if showsGameweekNumbers {
                        Text("GW\(week.gameweek)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    FixtureCell(week: week, compact: compact)
                }
            }
        }
    }
}

/// The next five gameweeks for everyone in the starting XI.
///
/// Sitting next to the pitch, this answers the question the projection can only
/// summarise: *who* each player actually faces. The model already weighs
/// difficulty, but a manager wants to see the run before trusting it.
struct FixtureTickerCard: View {
    @EnvironmentObject var state: AppState
    let squad: OptimizedSquad
    var count = 5

    @State private var includeBench = false

    private var planner: FixturePlanner? { state.fixtures }

    private var players: [RatedPlayer] {
        includeBench ? squad.starting + squad.bench : squad.starting
    }

    private var gameweeks: [Int] {
        Array(planner?.actionableGameweeks.prefix(count) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Next \(count) fixtures", systemImage: "calendar")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Button(includeBench ? "XI only" : "Show bench") {
                    withAnimation(.easeInOut(duration: 0.18)) { includeBench.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.mint)
                .buttonStyle(.plain)
            }

            if let planner, !gameweeks.isEmpty {
                // Column headings line up with the cells below.
                HStack(spacing: 3) {
                    Text("")
                        .frame(width: 74, alignment: .leading)
                    ForEach(gameweeks, id: \.self) { gameweek in
                        Text("GW\(gameweek)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(players) { player in
                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(player.element.webName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(player.team.shortName)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(width: 74, alignment: .leading)

                        FixtureRun(weeks: planner.next(count, for: player.element.team), compact: true)
                    }
                    .opacity(squad.bench.contains(where: { $0.id == player.id }) ? 0.6 : 1)
                }

                legend
            } else {
                Text("No fixtures scheduled yet.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach([1.5, 2.5, 3.0, 4.0, 5.0], id: \.self) { difficulty in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(FixtureTint.colour(difficulty, isBlank: false))
                            .frame(width: 11, height: 11)
                        Text(FixtureTint.label(difficulty))
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Text("Home fixtures in capitals, away in lower case. A dash is a blank gameweek; two names in one cell is a double.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}
