import Foundation

/// A finished suggestion: 15 legal players, a starting XI, captain and bench order.
struct OptimizedSquad {
    var squad: [RatedPlayer]              // all 15
    var starting: [RatedPlayer]           // 11, sorted GK → FWD
    var bench: [RatedPlayer]              // 4, in the order they should be subbed on
    var captain: RatedPlayer
    var viceCaptain: RatedPlayer
    var formation: String                 // e.g. "3-5-2"
    var totalCostTenths: Int
    var budgetTenths: Int
    var projectedPoints: Double           // XI, captain counted twice
    var notes: [String]
    var edited: Bool = false              // true once the user has changed it by hand

    var remainingTenths: Int { budgetTenths - totalCostTenths }
    /// Projected points of the XI before the captain's doubling.
    var startingPoints: Double { projectedPoints - captain.projected }

    func players(_ position: Position) -> [RatedPlayer] {
        starting.filter { $0.position == position }
    }
}

enum OptimizerError: LocalizedError {
    case notEnoughClubs(Int)
    case tooManyMustHaves(String)
    case cannotAfford(String)
    case emptyPool(Position)

    var errorDescription: String? {
        switch self {
        case .notEnoughClubs(let count):
            return "With a limit of \(count) players per club you need at least \(Int(ceil(15.0 / Double(count)))) clubs selected to fill a 15-man squad."
        case .tooManyMustHaves(let detail):
            return "Your must-have list doesn't fit a legal squad: \(detail)"
        case .cannotAfford(let detail):
            return "That budget can't cover a legal 15-man squad: \(detail)"
        case .emptyPool(let position):
            return "No \(position.name.lowercased())s match your filters."
        }
    }
}

/// Builds the best legal FPL squad it can find under the user's constraints.
///
/// The search starts from the cheapest legal squad (always feasible), then does
/// best-improvement hill climbing on single-player swaps, with random
/// perturbation restarts to escape local optima. Every candidate is scored by
/// the value of its best starting XI, so bench spending is naturally minimised.
struct SquadOptimizer {
    let rated: [RatedPlayer]
    let prefs: Preferences

    /// Bench points are worth much less than XI points, but not nothing.
    private static let benchWeight = 0.12
    private let restarts = 8
    private let maxPasses = 40

    init(rated: [RatedPlayer], prefs: Preferences) {
        self.rated = rated
        self.prefs = prefs
    }

    // MARK: - Entry point

    func optimize() throws -> OptimizedSquad {
        var notes: [String] = []
        let budget = prefs.budgetTenths

        if prefs.teamMode == .only {
            let clubs = prefs.preferredTeams.count
            let needed = Int(ceil(15.0 / Double(max(1, prefs.maxPerClub))))
            guard clubs >= needed else { throw OptimizerError.notEnoughClubs(prefs.maxPerClub) }
        }

        let locked = try lockedPlayers()
        let pool = try buildPool(locked: locked)

        var best = try cheapestFeasible(pool: pool, locked: locked, budget: budget)
        var bestScore = Self.evaluate(best).score
        var rng = SeededRandom(seed: optimizerSeed)

        for restart in 0..<restarts {
            var current = restart == 0 ? best : perturb(best, pool: pool, locked: locked, budget: budget, rng: &rng)
            var currentScore = Self.evaluate(current).score

            for _ in 0..<maxPasses {
                guard let move = bestSwap(in: current, score: currentScore, pool: pool, locked: locked, budget: budget)
                else { break }
                current[move.index] = move.incoming
                currentScore = move.score
            }

            if currentScore > bestScore {
                best = current
                bestScore = currentScore
            }
        }

        let evaluation = Self.evaluate(best)
        let cost = best.reduce(0) { $0 + $1.priceTenths }

        if !locked.isEmpty {
            notes.append("Locked in \(locked.count) must-have \(locked.count == 1 ? "player" : "players").")
        }
        if prefs.teamMode == .only && !prefs.preferredTeams.isEmpty {
            notes.append("Restricted to your \(prefs.preferredTeams.count) selected clubs.")
        }
        let starting = evaluation.starting.sorted { lhs, rhs in
            lhs.position.rawValue == rhs.position.rawValue
                ? lhs.projected > rhs.projected
                : lhs.position.rawValue < rhs.position.rawValue
        }
        let captain = evaluation.captain
        let vice = evaluation.starting
            .filter { $0.id != captain.id }
            .max(by: { $0.projected < $1.projected }) ?? captain

        // Bench order: goalkeeper always sits at slot 0, then most likely to
        // deliver if someone doesn't play.
        let benchOutfield = evaluation.bench
            .filter { $0.position != .goalkeeper }
            .sorted { $0.projected > $1.projected }
        let benchGK = evaluation.bench.filter { $0.position == .goalkeeper }

        return OptimizedSquad(
            squad: best,
            starting: starting,
            bench: benchGK + benchOutfield,
            captain: captain,
            viceCaptain: vice,
            formation: evaluation.formation,
            totalCostTenths: cost,
            budgetTenths: budget,
            projectedPoints: evaluation.startingSum + captain.projected,
            notes: notes
        )
    }

    // MARK: - Candidate pool

    private func lockedPlayers() throws -> [RatedPlayer] {
        let locked = rated.filter { prefs.mustInclude.contains($0.id) }
        var byPosition: [Position: Int] = [:]
        var byClub: [Int: Int] = [:]
        for player in locked {
            byPosition[player.position, default: 0] += 1
            byClub[player.element.team, default: 0] += 1
        }
        for (position, count) in byPosition where count > position.squadCount {
            throw OptimizerError.tooManyMustHaves("\(count) \(position.short) selected, only \(position.squadCount) fit.")
        }
        for (club, count) in byClub where count > prefs.maxPerClub {
            let name = locked.first(where: { $0.element.team == club })?.team.name ?? "one club"
            throw OptimizerError.tooManyMustHaves("\(count) players from \(name), limit is \(prefs.maxPerClub).")
        }
        let cost = locked.reduce(0) { $0 + $1.priceTenths }
        if cost > prefs.budgetTenths {
            throw OptimizerError.cannotAfford("your must-haves alone cost \(formatPrice(tenths: cost)).")
        }
        return locked
    }

    /// A trimmed shortlist per position: the best scorers, the best value, and
    /// the cheapest bodies needed to fund them.
    private func buildPool(locked: [RatedPlayer]) throws -> [Position: [RatedPlayer]] {
        var pool: [Position: [RatedPlayer]] = [:]

        for position in Position.allCases {
            var eligible = rated.filter { player in
                guard player.position == position else { return false }
                if prefs.exclude.contains(player.id) { return false }
                if prefs.mustInclude.contains(player.id) { return false }   // locked separately
                if prefs.teamMode == .only && !prefs.preferredTeams.isEmpty
                    && !prefs.preferredTeams.contains(player.element.team) { return false }
                if prefs.avoidInjuryRisk {
                    if case .out = player.availability { return false }
                }
                return true
            }

            guard !eligible.isEmpty else { throw OptimizerError.emptyPool(position) }

            let byPoints = eligible.sorted { $0.projected > $1.projected }.prefix(45)
            let byValue = eligible.sorted { $0.valueRatio > $1.valueRatio }.prefix(45)
            let cheapest = eligible.sorted { $0.priceTenths < $1.priceTenths }.prefix(14)

            var seen = Set<Int>()
            var shortlist: [RatedPlayer] = []
            for player in byPoints + byValue + cheapest where seen.insert(player.id).inserted {
                shortlist.append(player)
            }
            eligible = shortlist
            pool[position] = eligible
        }
        return pool
    }

    // MARK: - Feasible starting point

    private func cheapestFeasible(pool: [Position: [RatedPlayer]],
                                  locked: [RatedPlayer],
                                  budget: Int) throws -> [RatedPlayer] {
        var squad = locked
        var clubCounts: [Int: Int] = [:]
        for player in locked { clubCounts[player.element.team, default: 0] += 1 }
        var chosen = Set(locked.map(\.id))

        for position in Position.allCases {
            let needed = position.squadCount - locked.filter { $0.position == position }.count
            guard needed > 0 else { continue }
            let candidates = (pool[position] ?? []).sorted { $0.priceTenths < $1.priceTenths }
            var added = 0
            for player in candidates where added < needed {
                guard !chosen.contains(player.id) else { continue }
                guard clubCounts[player.element.team, default: 0] < prefs.maxPerClub else { continue }
                squad.append(player)
                chosen.insert(player.id)
                clubCounts[player.element.team, default: 0] += 1
                added += 1
            }
            guard added == needed else {
                throw OptimizerError.tooManyMustHaves("not enough \(position.name.lowercased())s available under the per-club limit.")
            }
        }

        let cost = squad.reduce(0) { $0 + $1.priceTenths }
        guard cost <= budget else {
            throw OptimizerError.cannotAfford("the cheapest legal squad under your filters costs \(formatPrice(tenths: cost)).")
        }
        return squad
    }

    // MARK: - Local search

    private struct Move {
        let index: Int
        let incoming: RatedPlayer
        let score: Double
    }

    private func bestSwap(in squad: [RatedPlayer],
                          score: Double,
                          pool: [Position: [RatedPlayer]],
                          locked: [RatedPlayer],
                          budget: Int) -> Move? {
        let lockedIDs = Set(locked.map(\.id))
        let squadIDs = Set(squad.map(\.id))
        let cost = squad.reduce(0) { $0 + $1.priceTenths }
        var clubCounts: [Int: Int] = [:]
        for player in squad { clubCounts[player.element.team, default: 0] += 1 }

        var best: Move?
        var bestScore = score
        var trial = squad

        for (index, outgoing) in squad.enumerated() {
            guard !lockedIDs.contains(outgoing.id) else { continue }
            let candidates = pool[outgoing.position] ?? []
            let headroom = budget - cost + outgoing.priceTenths

            for incoming in candidates {
                guard !squadIDs.contains(incoming.id) else { continue }
                guard incoming.priceTenths <= headroom else { continue }
                if incoming.element.team != outgoing.element.team {
                    guard clubCounts[incoming.element.team, default: 0] < prefs.maxPerClub else { continue }
                }
                trial[index] = incoming
                let candidateScore = Self.evaluate(trial).score
                if candidateScore > bestScore + 0.0001 {
                    bestScore = candidateScore
                    best = Move(index: index, incoming: incoming, score: candidateScore)
                }
            }
            trial[index] = outgoing
        }
        return best
    }

    private func perturb(_ squad: [RatedPlayer],
                         pool: [Position: [RatedPlayer]],
                         locked: [RatedPlayer],
                         budget: Int,
                         rng: inout SeededRandom) -> [RatedPlayer] {
        let lockedIDs = Set(locked.map(\.id))
        var result = squad
        var squadIDs = Set(squad.map(\.id))
        var clubCounts: [Int: Int] = [:]
        for player in squad { clubCounts[player.element.team, default: 0] += 1 }
        var cost = squad.reduce(0) { $0 + $1.priceTenths }

        let swappable = squad.indices.filter { !lockedIDs.contains(squad[$0].id) }
        guard swappable.count >= 2 else { return squad }

        for _ in 0..<2 {
            let index = swappable[rng.next(upTo: swappable.count)]
            let outgoing = result[index]
            let candidates = (pool[outgoing.position] ?? []).filter { candidate in
                !squadIDs.contains(candidate.id)
                    && candidate.priceTenths <= budget - cost + outgoing.priceTenths
                    && (candidate.element.team == outgoing.element.team
                        || clubCounts[candidate.element.team, default: 0] < prefs.maxPerClub)
            }
            guard !candidates.isEmpty else { continue }
            let incoming = candidates[rng.next(upTo: candidates.count)]

            squadIDs.remove(outgoing.id)
            squadIDs.insert(incoming.id)
            clubCounts[outgoing.element.team, default: 1] -= 1
            clubCounts[incoming.element.team, default: 0] += 1
            cost += incoming.priceTenths - outgoing.priceTenths
            result[index] = incoming
        }
        return result
    }

    // MARK: - Objective

    struct Evaluation {
        var score: Double
        var startingSum: Double
        var starting: [RatedPlayer]
        var bench: [RatedPlayer]
        var captain: RatedPlayer
        var formation: String
    }

    /// Picks the best legal XI out of the 15 and scores the squad.
    static func evaluate(_ squad: [RatedPlayer]) -> Evaluation {
        var byPosition: [Position: [RatedPlayer]] = [:]
        for player in squad { byPosition[player.position, default: []].append(player) }
        for key in byPosition.keys {
            byPosition[key]?.sort { $0.projected > $1.projected }
        }

        let keepers = byPosition[.goalkeeper] ?? []
        let defenders = byPosition[.defender] ?? []
        let midfielders = byPosition[.midfielder] ?? []
        let forwards = byPosition[.forward] ?? []

        func prefix(_ players: [RatedPlayer]) -> [Double] {
            var sums = [0.0]
            for player in players { sums.append(sums.last! + player.projected) }
            return sums
        }
        let defSums = prefix(defenders)
        let midSums = prefix(midfielders)
        let fwdSums = prefix(forwards)

        var bestTotal = -Double.infinity
        var bestShape = (def: 3, mid: 4, fwd: 3)

        for def in Position.defender.startingRange where def < defSums.count {
            for mid in Position.midfielder.startingRange where mid < midSums.count {
                let fwd = 10 - def - mid
                guard Position.forward.startingRange.contains(fwd), fwd < fwdSums.count else { continue }
                let total = defSums[def] + midSums[mid] + fwdSums[fwd]
                if total > bestTotal {
                    bestTotal = total
                    bestShape = (def, mid, fwd)
                }
            }
        }

        let keeper = keepers.first
        var starting: [RatedPlayer] = []
        if let keeper { starting.append(keeper) }
        starting += defenders.prefix(bestShape.def)
        starting += midfielders.prefix(bestShape.mid)
        starting += forwards.prefix(bestShape.fwd)

        let startingIDs = Set(starting.map(\.id))
        let bench = squad.filter { !startingIDs.contains($0.id) }

        let startingSum = starting.reduce(0) { $0 + $1.projected }
        let benchSum = bench.reduce(0) { $0 + $1.projected }
        let captain = starting.max(by: { $0.projected < $1.projected }) ?? squad[0]

        return Evaluation(
            score: startingSum + captain.projected + benchWeight * benchSum,
            startingSum: startingSum,
            starting: starting,
            bench: bench,
            captain: captain,
            formation: "\(bestShape.def)-\(bestShape.mid)-\(bestShape.fwd)"
        )
    }
}

/// Deterministic RNG so the same inputs always produce the same suggestion.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(next() % UInt64(bound))
    }
}

/// Fixed seed keeps the perturbation restarts reproducible run to run.
private let optimizerSeed: UInt64 = 20_260_821
