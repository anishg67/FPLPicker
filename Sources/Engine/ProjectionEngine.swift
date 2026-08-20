import Foundation

/// A player with a projected points-per-gameweek score and the reasoning behind it.
struct RatedPlayer: Identifiable, Hashable {
    let element: Element
    let team: FPLTeam
    var projected: Double          // expected FPL points per gameweek
    var baseRate: Double           // scoring rate before fixture/availability adjustment
    var fixtureScore: Double       // average FDR over the horizon (1 easy ... 5 hard)
    var minutesShare: Double       // 0...1 share of available minutes played
    var availability: Availability
    var reasons: [String]

    var id: Int { element.id }
    var position: Position { element.position }
    var priceTenths: Int { element.priceTenths }
    /// Points per gameweek per £1m — the value metric the optimizer leans on.
    var valueRatio: Double { projected / max(0.1, Double(priceTenths) / 10.0) }

    static func == (lhs: RatedPlayer, rhs: RatedPlayer) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(element.id) }
}

/// Turns raw FPL stats into a single expected-points-per-gameweek number.
///
/// The model blends three signals — recent form, season-long returns, and
/// underlying per-90 numbers (xG/xA, clean sheet and save rates) — then scales
/// the result by fixture difficulty, minutes security and injury status.
struct ProjectionEngine {
    let data: LeagueData
    let prefs: Preferences

    private let teamsByID: [Int: FPLTeam]
    private let fdrByTeam: [Int: Double]        // avg difficulty over the horizon
    private let fixtureCountByTeam: [Int: Int]
    private let maxMinutes: Double

    init(data: LeagueData, prefs: Preferences) {
        self.data = data
        self.prefs = prefs
        self.teamsByID = data.teamsByID

        let horizon = max(1, min(10, prefs.fixtureHorizon))
        let upcoming = ProjectionEngine.upcomingFixtures(data.fixtures, horizon: horizon)

        var difficultySum: [Int: Int] = [:]
        var counts: [Int: Int] = [:]
        for fixture in upcoming {
            difficultySum[fixture.teamH, default: 0] += fixture.teamHDifficulty
            counts[fixture.teamH, default: 0] += 1
            difficultySum[fixture.teamA, default: 0] += fixture.teamADifficulty
            counts[fixture.teamA, default: 0] += 1
        }
        var averages: [Int: Double] = [:]
        for (team, sum) in difficultySum {
            let count = counts[team] ?? 1
            averages[team] = Double(sum) / Double(max(1, count))
        }
        self.fdrByTeam = averages
        self.fixtureCountByTeam = counts
        self.maxMinutes = max(90, data.elements.map { Double($0.minutes) }.max() ?? 90)
    }

    /// Fixtures for the next `horizon` scheduled gameweeks.
    private static func upcomingFixtures(_ fixtures: [Fixture], horizon: Int) -> [Fixture] {
        let pending = fixtures.filter { !$0.finished }
        let events = Set(pending.compactMap { $0.event }).sorted()
        guard let first = events.first else { return pending }
        let window = Set(events.filter { $0 < first + horizon })
        return pending.filter { fixture in
            guard let event = fixture.event else { return false }
            return window.contains(event)
        }
    }

    func rateAll() -> [RatedPlayer] {
        data.elements.compactMap { rate($0) }
    }

    func rate(_ element: Element) -> RatedPlayer? {
        guard let team = teamsByID[element.team] else { return nil }
        var reasons: [String] = []

        // 1. Scoring rate ------------------------------------------------------
        let perGame = element.pointsPerGame.value
        let per90 = element.minutes >= 270
            ? Double(element.totalPoints) / (Double(element.minutes) / 90.0)
            : perGame
        let seasonRate = element.minutes >= 270 ? (0.5 * perGame + 0.5 * per90) : perGame

        let formRate = element.form.value
        let hasForm = formRate > 0
        let formWeight = hasForm ? max(0, min(1, prefs.formWeight)) : 0
        var base = formWeight * formRate + (1 - formWeight) * seasonRate

        // FPL publishes its own expected points for the next gameweek; use it as
        // a third anchor when it is present.
        let epNext = element.epNext.value
        if epNext > 0 { base = 0.72 * base + 0.28 * epNext }

        // Underlying numbers catch players whose returns haven't landed yet.
        let underlying = underlyingRate(element)
        if underlying > 0 { base = 0.75 * base + 0.25 * underlying }

        // Nudge for penalty duty — the single biggest source of cheap points.
        if let order = element.penaltiesOrder, order == 1, element.position != .goalkeeper {
            base *= 1.08
            reasons.append("On penalties")
        }

        // 2. Fixtures ----------------------------------------------------------
        let fdr = fdrByTeam[element.team] ?? 3.0
        let games = fixtureCountByTeam[element.team] ?? 1
        var fixtureMultiplier = 1.0 + (3.0 - fdr) * 0.10
        // A double gameweek (or a blank) genuinely changes expected returns.
        let horizon = max(1, min(10, prefs.fixtureHorizon))
        let gamesPerWeek = Double(games) / Double(horizon)
        if gamesPerWeek > 1.05 { fixtureMultiplier *= min(1.35, gamesPerWeek) }
        if gamesPerWeek < 0.95 { fixtureMultiplier *= max(0.6, gamesPerWeek) }
        fixtureMultiplier = min(1.45, max(0.6, fixtureMultiplier))

        if fdr <= 2.4 { reasons.append(String(format: "Kind fixtures (avg FDR %.1f)", fdr)) }
        if fdr >= 3.8 { reasons.append(String(format: "Tough run (avg FDR %.1f)", fdr)) }

        // 3. Minutes security ---------------------------------------------------
        let minutesShare = min(1.0, Double(element.minutes) / maxMinutes)
        let strictness = prefs.avoidInjuryRisk ? 0.45 : 0.25
        let minutesFactor = (1 - strictness) + strictness * minutesShare
        if minutesShare > 0.85 { reasons.append("Nailed starter") }
        else if minutesShare < 0.35 && element.minutes > 0 { reasons.append("Rotation risk") }

        // 4. Availability -------------------------------------------------------
        let availability = element.availability
        var availabilityFactor = availability.multiplier
        if prefs.avoidInjuryRisk, case .doubtful = availability { availabilityFactor *= 0.8 }
        if let label = availability.label { reasons.append(label) }

        // 5. Risk appetite ------------------------------------------------------
        // Positive appetite rewards low ownership, negative rewards the template.
        let ownership = element.ownership
        let ownershipTilt = (15.0 - min(60.0, ownership)) / 100.0
        let riskFactor = 1.0 + prefs.riskAppetite * ownershipTilt * 0.9
        if prefs.riskAppetite > 0.25 && ownership < 8 {
            reasons.append(String(format: "Differential (%.1f%% owned)", ownership))
        }
        if prefs.riskAppetite < -0.25 && ownership > 25 {
            reasons.append(String(format: "Template pick (%.0f%% owned)", ownership))
        }

        // 6. Club preference (soft bias mode only) ------------------------------
        var teamBias = 1.0
        if prefs.teamMode == .bias, prefs.preferredTeams.contains(element.team) {
            teamBias = 1.12
            reasons.append("Your club: \(team.shortName)")
        }

        let projected = max(0, base * fixtureMultiplier * minutesFactor
                            * availabilityFactor * riskFactor * teamBias)

        if formRate >= 6 { reasons.insert("Hot form (\(String(format: "%.1f", formRate)))", at: 0) }
        if element.priceTenths <= 45 && projected >= 2.6 { reasons.append("Great value at \(formatPrice(tenths: element.priceTenths))") }

        return RatedPlayer(
            element: element,
            team: team,
            projected: projected,
            baseRate: base,
            fixtureScore: fdr,
            minutesShare: minutesShare,
            availability: availability,
            reasons: Array(reasons.prefix(3))
        )
    }

    /// Expected points per 90 implied by underlying stats, by position.
    private func underlyingRate(_ element: Element) -> Double {
        guard element.minutes >= 270 else { return 0 }
        let xg = element.expectedGoalsPer90.value
        let xa = element.expectedAssistsPer90.value
        let cs = element.cleanSheetsPer90.value
        let saves = element.savesPer90.value
        let defensive = element.defensiveContributionPer90.value

        switch element.position {
        case .goalkeeper:
            return 2.0 + cs * 4.0 + saves / 3.0
        case .defender:
            return 2.0 + cs * 4.0 + xg * 6.0 + xa * 3.0 + defensive * 0.15
        case .midfielder:
            return 2.0 + cs * 1.0 + xg * 5.0 + xa * 3.0 + defensive * 0.12
        case .forward:
            return 2.0 + xg * 4.0 + xa * 3.0
        }
    }
}
