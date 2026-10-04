import Foundation

/// One suggested swap and what it's worth.
struct TransferMove: Identifiable, Equatable {
    let outgoing: RatedPlayer
    let incoming: RatedPlayer
    /// Improvement in projected squad points per gameweek.
    let gain: Double

    var id: String { "\(outgoing.id)->\(incoming.id)" }
    var priceDelta: Int { incoming.priceTenths - outgoing.priceTenths }

    static func == (lhs: TransferMove, rhs: TransferMove) -> Bool { lhs.id == rhs.id }
}

/// A recommended set of transfers, and the arithmetic behind whether it's worth it.
struct TransferPlan {
    var moves: [TransferMove]
    var alternatives: [TransferMove]
    var freeTransfers: Int
    var bankTenths: Int

    var hits: Int { max(0, moves.count - freeTransfers) }
    var pointsHit: Int { hits * 4 }
    var grossGain: Double { moves.reduce(0) { $0 + $1.gain } }
    /// Gain per gameweek once the −4s are paid for. Hits are one-off, so this is
    /// deliberately pessimistic: it charges the whole hit against a single week.
    var netGain: Double { grossGain - Double(pointsHit) }
    var isEmpty: Bool { moves.isEmpty }

    var bankAfter: Int {
        bankTenths - moves.reduce(0) { $0 + $1.priceDelta }
    }
}

/// What a set of transfers would do to the squad's projected score.
///
/// Expressed in the same currency as everything else on the squad screen — the
/// best legal XI with the captain doubled — so the number before and the number
/// after are directly comparable.
struct TransferOutlook {
    /// Projected points for the squad as it stands.
    var before: Double
    /// Projected points once the selected transfers are applied.
    var after: Double
    /// Transfers that would actually land, in order.
    var applied: [TransferMove]
    /// Transfers that were selected but turned out to be illegal alongside the
    /// others, so they were dropped.
    var rejected: [TransferMove]
    var freeTransfers: Int
    var bankBefore: Int
    var bankAfter: Int

    var count: Int { applied.count }
    var hits: Int { max(0, count - freeTransfers) }
    var pointsHit: Int { hits * 4 }
    /// Raw improvement per gameweek, before any hit is charged.
    var gain: Double { after - before }
    /// What you actually bank this week, with the hit paid for.
    var net: Double { gain - Double(pointsHit) }
    var isEmpty: Bool { applied.isEmpty }

    /// How many gameweeks the gain has to hold for the hit to pay for itself.
    /// Nil when there's no hit, or when the move loses points anyway.
    var weeksToBreakEven: Int? {
        guard pointsHit > 0, gain > 0 else { return nil }
        return Int((Double(pointsHit) / gain).rounded(.up))
    }
}

/// Suggests transfers for a squad the user already owns.
///
/// Works the same way the optimizer scores squads — best legal XI plus captain,
/// bench discounted — so a transfer only scores well if it improves the team
/// the user actually fields.
struct TransferPlanner {
    let squad: [RatedPlayer]
    let rated: [RatedPlayer]
    let bankTenths: Int
    let freeTransfers: Int
    let maxPerClub: Int

    /// Deep enough to catch value picks, shallow enough to stay instant.
    private let candidatesPerPosition = 70

    func plan() -> TransferPlan {
        var current = squad
        var bank = bankTenths
        var moves: [TransferMove] = []

        // One transfer beyond the free ones is considered, but only if it beats
        // the 4-point charge on its own.
        let ceiling = max(freeTransfers, 1) + 1

        for step in 0..<ceiling {
            guard let best = bestMove(in: current, bank: bank) else { break }
            let payingAHit = step >= freeTransfers
            if payingAHit && best.gain <= 4.0 { break }
            if best.gain <= 0.05 { break }

            guard isLegal(best, in: current, bank: bank) else { break }
            moves.append(best)
            bank -= best.priceDelta
            current = current.map { $0.id == best.outgoing.id ? best.incoming : $0 }
        }

        // Alternatives are offered alongside the plan, so they have to be legal
        // *after* it — the plan's own moves have already changed the club counts
        // and the bank. Ranking them against the original squad produced
        // suggestions that would break the three-per-club limit once applied.
        let alternatives = rankedMoves(in: current, bank: bank)
            .filter { move in !moves.contains(where: { $0.outgoing.id == move.outgoing.id }) }
            .filter { isLegal($0, in: current, bank: bank) }
            .prefix(5)

        return TransferPlan(
            moves: moves,
            alternatives: Array(alternatives),
            freeTransfers: freeTransfers,
            bankTenths: bankTenths
        )
    }

    // MARK: - Search

    /// Whether a move would still be legal applied to this squad: same
    /// position, inside the bank, and within the club limit.
    ///
    /// The ranking already enforces all three, but every suggestion is checked
    /// again before it is offered. A move is generated against one squad and
    /// may be shown beside others that have since changed it, and an illegal
    /// suggestion is worse than a missing one.
    func isLegal(_ move: TransferMove, in squad: [RatedPlayer], bank: Int) -> Bool {
        guard move.outgoing.position == move.incoming.position else { return false }
        guard squad.contains(where: { $0.id == move.outgoing.id }) else { return false }
        guard !squad.contains(where: { $0.id == move.incoming.id }) else { return false }
        guard move.priceDelta <= bank else { return false }
        if move.incoming.element.team != move.outgoing.element.team {
            let atClub = squad.filter { $0.element.team == move.incoming.element.team }.count
            guard atClub < maxPerClub else { return false }
        }
        return true
    }

    /// Applies moves one at a time, skipping any that stops being legal once
    /// the earlier ones have landed.
    ///
    /// The user ticks moves in any order, and two perfectly good suggestions can
    /// be illegal together — both selling into the same club, or both selling
    /// the same player. Rather than refuse the whole selection, this takes what
    /// it can and reports what it dropped.
    func resolve(_ moves: [TransferMove], bank: Int) -> (applied: [TransferMove],
                                                         rejected: [TransferMove],
                                                         squad: [RatedPlayer],
                                                         bank: Int) {
        var current = squad
        var remaining = bank
        var applied: [TransferMove] = []
        var rejected: [TransferMove] = []

        for move in moves {
            guard isLegal(move, in: current, bank: remaining) else {
                rejected.append(move)
                continue
            }
            applied.append(move)
            remaining -= move.priceDelta
            current = current.map { $0.id == move.outgoing.id ? move.incoming : $0 }
        }
        return (applied, rejected, current, remaining)
    }

    /// Projected points — best legal XI, captain doubled — for any 15.
    static func projectedPoints(of squad: [RatedPlayer]) -> Double {
        let evaluation = SquadOptimizer.evaluate(squad)
        return evaluation.startingSum + evaluation.captain.projected
    }

    /// What the squad would score with `moves` applied, and what it scores now.
    func outlook(applying moves: [TransferMove]) -> TransferOutlook {
        let resolved = resolve(moves, bank: bankTenths)
        return TransferOutlook(
            before: Self.projectedPoints(of: squad),
            after: Self.projectedPoints(of: resolved.squad),
            applied: resolved.applied,
            rejected: resolved.rejected,
            freeTransfers: freeTransfers,
            bankBefore: bankTenths,
            bankAfter: resolved.bank
        )
    }

    private func bestMove(in squad: [RatedPlayer], bank: Int) -> TransferMove? {
        rankedMoves(in: squad, bank: bank).first
    }

    /// Every legal single swap, best first.
    func rankedMoves(in squad: [RatedPlayer], bank: Int) -> [TransferMove] {
        let squadIDs = Set(squad.map(\.id))
        var clubCounts: [Int: Int] = [:]
        for player in squad { clubCounts[player.element.team, default: 0] += 1 }

        let baseline = SquadOptimizer.evaluate(squad).score
        var moves: [TransferMove] = []
        var trial = squad

        for (index, outgoing) in squad.enumerated() {
            let headroom = bank + outgoing.priceTenths
            let candidates = pool(for: outgoing.position)

            for incoming in candidates {
                guard !squadIDs.contains(incoming.id) else { continue }
                guard incoming.priceTenths <= headroom else { continue }
                if incoming.element.team != outgoing.element.team {
                    guard clubCounts[incoming.element.team, default: 0] < maxPerClub else { continue }
                }
                trial[index] = incoming
                let gain = SquadOptimizer.evaluate(trial).score - baseline
                if gain > 0.05 {
                    moves.append(TransferMove(outgoing: outgoing, incoming: incoming, gain: gain))
                }
            }
            trial[index] = outgoing
        }
        return moves.sorted { $0.gain > $1.gain }
    }

    private func pool(for position: Position) -> [RatedPlayer] {
        rated
            .filter { $0.position == position }
            .filter { player in
                if case .out = player.availability { return false }
                return true
            }
            .sorted { $0.projected > $1.projected }
            .prefix(candidatesPerPosition)
            .map { $0 }
    }
}
