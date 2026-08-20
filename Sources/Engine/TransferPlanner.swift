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

            moves.append(best)
            bank -= best.priceDelta
            current = current.map { $0.id == best.outgoing.id ? best.incoming : $0 }
        }

        let alternatives = rankedMoves(in: squad, bank: bankTenths)
            .filter { move in !moves.contains(where: { $0.outgoing.id == move.outgoing.id }) }
            .prefix(5)

        return TransferPlan(
            moves: moves,
            alternatives: Array(alternatives),
            freeTransfers: freeTransfers,
            bankTenths: bankTenths
        )
    }

    // MARK: - Search

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
