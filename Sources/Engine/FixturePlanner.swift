import Foundation

/// One scheduled match from a given club's point of view.
struct UpcomingFixture: Identifiable, Hashable {
    let id: Int
    let gameweek: Int
    let opponent: FPLTeam
    let isHome: Bool
    let difficulty: Int

    /// "ARS (H)" — the form used when there's room to spell it out.
    var label: String { "\(opponent.shortName) (\(isHome ? "H" : "A"))" }
    /// Home fixtures in capitals, away in lower case, the way tickers show them.
    var ticker: String { isHome ? opponent.shortName.uppercased() : opponent.shortName.lowercased() }
}

/// What a club faces in one gameweek: usually one match, sometimes two, and in
/// a blank gameweek none at all.
struct GameweekFixtures: Identifiable, Hashable {
    let gameweek: Int
    let fixtures: [UpcomingFixture]

    var id: Int { gameweek }
    var isBlank: Bool { fixtures.isEmpty }
    var isDouble: Bool { fixtures.count > 1 }

    /// Average difficulty across the gameweek. A blank is the worst case: no
    /// points at all, so it scores worse than the hardest single fixture.
    var difficulty: Double {
        guard !fixtures.isEmpty else { return 5 }
        return Double(fixtures.reduce(0) { $0 + $1.difficulty }) / Double(fixtures.count)
    }

    var ticker: String {
        fixtures.isEmpty ? "—" : fixtures.map(\.ticker).joined(separator: " ")
    }
}

/// Looks up what each club has coming, for the fixture ticker.
///
/// Works in gameweeks rather than matches so that doubles and blanks show up as
/// themselves. Five matches ahead and five gameweeks ahead are different things
/// once the cup rounds start moving fixtures around, and the gameweek is the
/// unit a manager actually plans in.
struct FixturePlanner {
    let data: LeagueData

    private let byGameweek: [Int: [Int: [UpcomingFixture]]]   // gameweek -> team -> fixtures
    /// Gameweeks whose deadline hasn't passed, soonest first.
    let actionableGameweeks: [Int]

    init(data: LeagueData) {
        self.data = data
        let teamsByID = data.teamsByID

        var table: [Int: [Int: [UpcomingFixture]]] = [:]
        for fixture in data.fixtures where !fixture.finished {
            guard let gameweek = fixture.event else { continue }
            if let away = teamsByID[fixture.teamA] {
                table[gameweek, default: [:]][fixture.teamH, default: []].append(
                    UpcomingFixture(id: fixture.id, gameweek: gameweek, opponent: away,
                                    isHome: true, difficulty: fixture.teamHDifficulty))
            }
            if let home = teamsByID[fixture.teamH] {
                table[gameweek, default: [:]][fixture.teamA, default: []].append(
                    UpcomingFixture(id: fixture.id, gameweek: gameweek, opponent: home,
                                    isHome: false, difficulty: fixture.teamADifficulty))
            }
        }
        self.byGameweek = table

        let now = Date()
        self.actionableGameweeks = data.events
            .filter { !$0.finished }
            .filter { ($0.deadlineTime ?? .distantPast) > now }
            .map(\.id)
            .sorted()
    }

    /// The next `count` gameweeks for a club, blanks included.
    func next(_ count: Int = 5, for team: Int) -> [GameweekFixtures] {
        actionableGameweeks.prefix(count).map { gameweek in
            GameweekFixtures(gameweek: gameweek,
                             fixtures: byGameweek[gameweek]?[team] ?? [])
        }
    }

    /// Average difficulty over that run, for sorting and for a one-line summary.
    func averageDifficulty(_ count: Int = 5, for team: Int) -> Double {
        let weeks = next(count, for: team)
        guard !weeks.isEmpty else { return 3 }
        return weeks.reduce(0) { $0 + $1.difficulty } / Double(weeks.count)
    }

    /// Plain-English read on a run of fixtures.
    func summary(_ count: Int = 5, for team: Int) -> String {
        let weeks = next(count, for: team)
        guard !weeks.isEmpty else { return "No fixtures scheduled yet." }
        let blanks = weeks.filter(\.isBlank).count
        let doubles = weeks.filter(\.isDouble).count
        let average = averageDifficulty(count, for: team)

        var parts: [String] = []
        switch average {
        case ..<2.5: parts.append("Kind run")
        case ..<3.5: parts.append("Average run")
        default: parts.append("Tough run")
        }
        parts.append(String(format: "avg FDR %.1f", average))
        if doubles > 0 { parts.append("\(doubles) double\(doubles == 1 ? "" : "s")") }
        if blanks > 0 { parts.append("\(blanks) blank\(blanks == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
