import Foundation

/// What the app thinks you should do with one chip.
struct ChipAdvice: Identifiable {
    enum Verdict {
        case play(gameweek: Int)
        case hold
        case used
        case expired

        var isPlay: Bool { if case .play = self { return true }; return false }
    }

    let chip: Chip
    let verdict: Verdict
    /// Points the chip adds over playing an ordinary week.
    let gain: Double
    /// How many times better than an ordinary week the best gameweek looks.
    let multiple: Double
    let headline: String
    let detail: String
    /// The best gameweeks found, strongest first, for showing the runners-up.
    let ranked: [(gameweek: Int, gain: Double)]

    var id: String { chip.rawValue }
}

/// Works out when to play each chip.
///
/// Every chip is valued in the same currency — points it would add over playing
/// the gameweek normally — so the four can be compared against each other and
/// against the rules of thumb for holding on.
struct ChipPlanner {
    let squad: OptimizedSquad
    let rated: [RatedPlayer]
    let data: LeagueData
    let usage: ChipUsage
    /// How far ahead to look. Chip windows still apply on top of this.
    let horizon: Int

    private let matchesByTeam: [Int: [Int: Int]]        // gameweek -> team -> fixtures
    private let difficultyByTeam: [Int: [Int: Double]]  // gameweek -> team -> avg FDR

    init(squad: OptimizedSquad, rated: [RatedPlayer], data: LeagueData,
         usage: ChipUsage, horizon: Int = 8) {
        self.squad = squad
        self.rated = rated
        self.data = data
        self.usage = usage
        self.horizon = horizon

        var matches: [Int: [Int: Int]] = [:]
        var difficulty: [Int: [Int: [Int]]] = [:]
        for fixture in data.fixtures where !fixture.finished {
            guard let gameweek = fixture.event else { continue }
            matches[gameweek, default: [:]][fixture.teamH, default: 0] += 1
            matches[gameweek, default: [:]][fixture.teamA, default: 0] += 1
            difficulty[gameweek, default: [:]][fixture.teamH, default: []].append(fixture.teamHDifficulty)
            difficulty[gameweek, default: [:]][fixture.teamA, default: []].append(fixture.teamADifficulty)
        }
        self.matchesByTeam = matches
        self.difficultyByTeam = difficulty.mapValues { perTeam in
            perTeam.mapValues { list in
                list.isEmpty ? 3.0 : Double(list.reduce(0, +)) / Double(list.count)
            }
        }
    }

    // MARK: - Gameweek arithmetic

    /// Gameweeks you can still act on. A gameweek that has kicked off is no
    /// use for chip advice even though the game hasn't marked it finished — its
    /// deadline has gone.
    var upcomingGameweeks: [Int] {
        let now = Date()
        let pending = data.events
            .filter { !$0.finished }
            .filter { ($0.deadlineTime ?? .distantPast) > now }
            .map(\.id)
            .sorted()
        return Array(pending.prefix(horizon))
    }

    func matches(_ team: Int, in gameweek: Int) -> Int {
        matchesByTeam[gameweek]?[team] ?? 0
    }

    /// Expected points for a player in one specific gameweek, which is their
    /// per-match rate scaled by how many fixtures they have and how hard those
    /// fixtures are. A blank returns zero; a double roughly doubles.
    func expected(_ player: RatedPlayer, in gameweek: Int) -> Double {
        let count = matches(player.element.team, in: gameweek)
        guard count > 0 else { return 0 }
        let fdr = difficultyByTeam[gameweek]?[player.element.team] ?? 3.0
        let swing = min(1.35, max(0.7, 1.0 + (3.0 - fdr) * 0.10))
        return player.perMatch * Double(count) * swing
    }

    /// Teams with two or more fixtures in a gameweek, and teams with none.
    func doubles(in gameweek: Int) -> [String] {
        (matchesByTeam[gameweek] ?? [:])
            .filter { $0.value > 1 }
            .compactMap { data.teamsByID[$0.key]?.shortName }
            .sorted()
    }

    func blanks(in gameweek: Int) -> [String] {
        data.teams
            .filter { matches($0.id, in: gameweek) == 0 }
            .map(\.shortName)
            .sorted()
    }

    // MARK: - Plan

    func plan() -> [ChipAdvice] {
        Chip.allCases.map { advice(for: $0) }
    }

    private func window(for chip: Chip) -> ChipWindow? {
        // The half a chip belongs to is decided by the gameweeks it covers, so
        // pick whichever of the season's two windows still has room ahead.
        let gameweeks = upcomingGameweeks
        guard let first = gameweeks.first else { return nil }
        return data.chipWindows
            .filter { $0.name == chip.rawValue && $0.stopEvent >= first }
            .sorted { $0.startEvent < $1.startEvent }
            .first
    }

    private func advice(for chip: Chip) -> ChipAdvice {
        guard let window = window(for: chip) else {
            return ChipAdvice(chip: chip, verdict: .expired, gain: 0, multiple: 1, headline: "No window left",
                              detail: "This chip's window has closed for the season.",
                              ranked: [])
        }
        if usage.hasUsed(chip, secondHalf: window.isSecondHalf) {
            return ChipAdvice(chip: chip, verdict: .used, gain: 0,
                              multiple: 1, headline: "Already played",
                              detail: window.isSecondHalf
                                  ? "You've used this one. It doesn't come back."
                                  : "You've used the first-half one. A second becomes available in gameweek 20.",
                              ranked: [])
        }

        let candidates = upcomingGameweeks.filter { window.covers($0) }
        guard !candidates.isEmpty else {
            return ChipAdvice(chip: chip, verdict: .hold, gain: 0,
                              multiple: 1, headline: "Not yet",
                              detail: "This chip opens in gameweek \(window.startEvent).",
                              ranked: [])
        }

        let values = candidates.map { (gameweek: $0, value: value(of: chip, in: $0)) }
        let scored = values.sorted { $0.value > $1.value }

        guard let best = scored.first, best.value > 0 else {
            return ChipAdvice(chip: chip, verdict: .hold, gain: 0, multiple: 1, headline: "Hold",
                              detail: "Nothing to weigh yet.", ranked: [])
        }

        // An ordinary week for this chip, so a candidate can be judged against
        // it rather than against a points total whose scale drifts.
        let ordered = values.map(\.value).sorted()
        // The wildcard is judged against the squad you own rather than against
        // other gameweeks, so its value is already a ratio.
        let typical = chip == .wildcard ? 1.0 : max(0.01, ordered[ordered.count / 2])
        let multiple = best.value / typical

        // A multiple alone isn't enough: when a typical week is worth almost
        // nothing, dividing by it turns a one-point gain into "95x better".
        // The chip must also move the needle against what the squad scores that
        // week — at least a tenth of it.
        let weekScale = max(1, bestEleven(from: squad.squad, in: best.gameweek))
        let significant = chip == .wildcard || (best.value - typical) >= 0.10 * weekScale
        let worthIt = multiple >= chip.playMultiple && significant

        return ChipAdvice(
            chip: chip,
            verdict: worthIt ? .play(gameweek: best.gameweek) : .hold,
            gain: chip == .wildcard ? (best.value - 1) * 100 : max(0, best.value - typical),
            multiple: multiple,
            headline: worthIt ? "Play in gameweek \(best.gameweek)" : "Hold",
            detail: reasoning(for: chip, gameweek: best.gameweek,
                              value: best.value, typical: typical, worthIt: worthIt),
            ranked: scored.prefix(3).map { (gameweek: $0.gameweek, gain: $0.value) }
        )
    }

    // MARK: - What each chip is worth

    private func value(of chip: Chip, in gameweek: Int) -> Double {
        switch chip {
        case .benchBoost:   return benchBoostValue(gameweek)
        case .tripleCaptain: return tripleCaptainValue(gameweek)
        case .freeHit:      return freeHitValue(gameweek)
        case .wildcard:     return wildcardValue()
        }
    }

    /// Bench Boost is simply what the four bench players would score.
    private func benchBoostValue(_ gameweek: Int) -> Double {
        squad.bench.reduce(0) { $0 + expected($1, in: gameweek) }
    }

    /// Triple Captain adds one more helping of your best captain.
    private func tripleCaptainValue(_ gameweek: Int) -> Double {
        squad.starting
            .filter { $0.position != .goalkeeper }
            .map { expected($0, in: gameweek) }
            .max() ?? 0
    }

    /// Free Hit is worth the gap between the XI you could field for one week
    /// and the XI you actually have. The replacement XI is built greedily from
    /// players who have a fixture, respecting the three-per-club limit and the
    /// squad's own budget, so it stays a team you could really assemble.
    private func freeHitValue(_ gameweek: Int) -> Double {
        let yours = bestEleven(from: squad.squad, in: gameweek)
        let budget = squad.budgetTenths
        var clubs: [Int: Int] = [:]
        var spend = 0
        var picked: [RatedPlayer] = []

        let pool = rated
            .filter { expected($0, in: gameweek) > 0 }
            .sorted { expected($0, in: gameweek) > expected($1, in: gameweek) }

        for position in Position.allCases {
            let need = position.squadCount
            var taken = 0
            for player in pool where player.position == position && taken < need {
                guard clubs[player.element.team, default: 0] < 3 else { continue }
                // Leave enough for the cheapest bodies still to come.
                guard spend + player.priceTenths <= budget - (15 - picked.count - 1) * 40 else { continue }
                picked.append(player)
                clubs[player.element.team, default: 0] += 1
                spend += player.priceTenths
                taken += 1
            }
        }
        guard picked.count == 15 else { return 0 }
        return max(0, bestEleven(from: picked, in: gameweek) - yours)
    }

    /// Wildcard is judged over the whole horizon rather than one gameweek: how
    /// much better the optimizer's squad is than the one you own, per gameweek.
    private func wildcardValue() -> Double {
        var prefs = Preferences.default
        prefs.budgetTenths = squad.budgetTenths
        guard let ideal = try? SquadOptimizer(rated: rated, prefs: prefs).optimize() else { return 0 }
        // Expressed as a ratio against the squad you already own, so the
        // threshold ("8% better") holds whatever the projection scale is.
        guard squad.startingPoints > 0 else { return 0 }
        return ideal.startingPoints / squad.startingPoints
    }

    /// Best legal XI out of a 15 for one gameweek, using that week's fixtures.
    private func bestEleven(from players: [RatedPlayer], in gameweek: Int) -> Double {
        var byPosition: [Position: [Double]] = [:]
        for player in players {
            byPosition[player.position, default: []].append(expected(player, in: gameweek))
        }
        for key in byPosition.keys { byPosition[key]?.sort(by: >) }

        func take(_ position: Position, _ count: Int) -> Double {
            (byPosition[position] ?? []).prefix(count).reduce(0, +)
        }
        guard let keeper = byPosition[.goalkeeper]?.first else { return 0 }

        var best = 0.0
        for defenders in Position.defender.startingRange {
            for midfielders in Position.midfielder.startingRange {
                let forwards = 10 - defenders - midfielders
                guard Position.forward.startingRange.contains(forwards) else { continue }
                guard (byPosition[.defender]?.count ?? 0) >= defenders,
                      (byPosition[.midfielder]?.count ?? 0) >= midfielders,
                      (byPosition[.forward]?.count ?? 0) >= forwards else { continue }
                let total = keeper + take(.defender, defenders)
                    + take(.midfielder, midfielders) + take(.forward, forwards)
                best = max(best, total)
            }
        }
        return best
    }

    // MARK: - Explanations

    /// "1 pt" rather than "1 pts".
    private func points(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded) pt\(rounded == 1 ? "" : "s")"
    }

    private func reasoning(for chip: Chip, gameweek: Int, value: Double, typical: Double, worthIt: Bool) -> String {
        let extra = value - typical
        let doubled = doubles(in: gameweek)
        let blanked = blanks(in: gameweek)
        var notes: [String] = []

        switch chip {
        case .benchBoost:
            notes.append("Gameweek \(gameweek) is your bench's best week — about \(points(extra)) more than a typical one.")
        case .tripleCaptain:
            notes.append("Gameweek \(gameweek) is your captain's best week — about \(points(extra)) more than a typical one.")
        case .freeHit:
            notes.append("Gameweek \(gameweek) is where a one-week rebuild gains most — about \(points(extra)).")
        case .wildcard:
            notes.append(String(format: "A rebuilt squad projects about %.0f%% more per gameweek than yours.", (value - 1) * 100))
        }

        if !doubled.isEmpty {
            notes.append("Double gameweek for \(doubled.prefix(4).joined(separator: ", ")).")
        }
        if !blanked.isEmpty && chip == .freeHit {
            notes.append("\(blanked.count) clubs blank.")
        }

        if !worthIt {
            switch chip {
            case .benchBoost, .tripleCaptain, .freeHit:
                notes.append(doubled.isEmpty && blanked.isEmpty
                    ? "No doubles or blanks are scheduled yet — they're usually announced later, and that's normally when this chip pays."
                    : "Not enough better than an ordinary week to justify burning the chip.")
            case .wildcard:
                notes.append("Your squad is close enough to the best available one that a rebuild wouldn't pay for itself yet.")
            }
        }
        return notes.joined(separator: " ")
    }
}
