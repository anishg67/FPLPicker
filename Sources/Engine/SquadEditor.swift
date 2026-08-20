import Foundation

enum SquadEditError: LocalizedError {
    case wrongPosition(Position, Position)
    case alreadyInSquad(String)
    case overBudget(Int)
    case clubLimit(String, Int)
    case illegalFormation
    case notStarting(String)
    case missingPlayers(Int)

    var errorDescription: String? {
        switch self {
        case .wrongPosition(let have, let want):
            return "You can only swap a \(want.short) for another \(want.short) — that one is a \(have.short)."
        case .alreadyInSquad(let name):
            return "\(name) is already in your squad."
        case .overBudget(let by):
            return "That puts you \(formatPrice(tenths: by)) over budget."
        case .clubLimit(let club, let limit):
            return "You'd have more than \(limit) players from \(club)."
        case .illegalFormation:
            return "That leaves an illegal formation — you need 1 keeper, 3-5 defenders, 2-5 midfielders and 1-3 forwards."
        case .notStarting(let name):
            return "\(name) is on the bench, so can't wear the armband."
        case .missingPlayers(let count):
            return "\(count) player\(count == 1 ? "" : "s") from that team are no longer in the game."
        }
    }
}

/// Manual edits to a built squad: transfers, substitutions and the armband.
/// Every mutation re-validates the FPL rules before it is applied.
enum SquadEditor {

    // MARK: - Transfers

    static func replace(_ squad: OptimizedSquad,
                        outgoing: RatedPlayer,
                        incoming: RatedPlayer,
                        maxPerClub: Int) throws -> OptimizedSquad {
        guard outgoing.position == incoming.position else {
            throw SquadEditError.wrongPosition(incoming.position, outgoing.position)
        }
        guard !squad.squad.contains(where: { $0.id == incoming.id }) else {
            throw SquadEditError.alreadyInSquad(incoming.element.webName)
        }
        let cost = squad.totalCostTenths - outgoing.priceTenths + incoming.priceTenths
        guard cost <= squad.budgetTenths else {
            throw SquadEditError.overBudget(cost - squad.budgetTenths)
        }
        if incoming.element.team != outgoing.element.team {
            let count = squad.squad.filter { $0.element.team == incoming.element.team }.count
            guard count < maxPerClub else {
                throw SquadEditError.clubLimit(incoming.team.name, maxPerClub)
            }
        }

        var next = squad
        next.squad = squad.squad.map { $0.id == outgoing.id ? incoming : $0 }
        next.starting = squad.starting.map { $0.id == outgoing.id ? incoming : $0 }
        next.bench = squad.bench.map { $0.id == outgoing.id ? incoming : $0 }
        if squad.captain.id == outgoing.id { next.captain = incoming }
        if squad.viceCaptain.id == outgoing.id { next.viceCaptain = incoming }
        next.edited = true
        return rebuilt(next)
    }

    // MARK: - Substitutions

    /// Bench players a starter can legally swap with (and vice versa).
    static func legalPartners(for player: RatedPlayer, in squad: OptimizedSquad) -> [RatedPlayer] {
        let isStarting = squad.starting.contains(where: { $0.id == player.id })
        let others = isStarting ? squad.bench : squad.starting
        return others.filter { partner in
            let starter = isStarting ? player : partner
            let sub = isStarting ? partner : player
            return isLegalStartingEleven(squad.starting.map { $0.id == starter.id ? sub : $0 })
        }
    }

    static func substitute(_ squad: OptimizedSquad,
                           starter: RatedPlayer,
                           substitute sub: RatedPlayer) throws -> OptimizedSquad {
        let starting = squad.starting.map { $0.id == starter.id ? sub : $0 }
        guard isLegalStartingEleven(starting) else { throw SquadEditError.illegalFormation }

        var bench = squad.bench.map { $0.id == sub.id ? starter : $0 }
        // The reserve keeper always sits in the first bench slot.
        bench = bench.filter { $0.position == .goalkeeper } + bench.filter { $0.position != .goalkeeper }

        var next = squad
        next.starting = starting
        next.bench = bench
        next.edited = true
        return rebuilt(next)
    }

    static func isLegalStartingEleven(_ players: [RatedPlayer]) -> Bool {
        guard players.count == 11 else { return false }
        for position in Position.allCases {
            let count = players.filter { $0.position == position }.count
            guard position.startingRange.contains(count) else { return false }
        }
        return true
    }

    // MARK: - Armband

    static func setCaptain(_ squad: OptimizedSquad, player: RatedPlayer) throws -> OptimizedSquad {
        guard squad.starting.contains(where: { $0.id == player.id }) else {
            throw SquadEditError.notStarting(player.element.webName)
        }
        var next = squad
        if squad.viceCaptain.id == player.id { next.viceCaptain = squad.captain }
        next.captain = player
        next.edited = true
        return rebuilt(next)
    }

    static func setViceCaptain(_ squad: OptimizedSquad, player: RatedPlayer) throws -> OptimizedSquad {
        guard squad.starting.contains(where: { $0.id == player.id }) else {
            throw SquadEditError.notStarting(player.element.webName)
        }
        var next = squad
        if squad.captain.id == player.id { next.captain = squad.viceCaptain }
        next.viceCaptain = player
        next.edited = true
        return rebuilt(next)
    }

    // MARK: - Auto XI

    /// Throws away manual bench choices and picks the highest-scoring legal XI.
    static func autoPickStartingEleven(_ squad: OptimizedSquad) -> OptimizedSquad {
        let evaluation = SquadOptimizer.evaluate(squad.squad)
        var next = squad
        next.starting = evaluation.starting
        next.bench = evaluation.bench.filter { $0.position == .goalkeeper }
            + evaluation.bench.filter { $0.position != .goalkeeper }
                .sorted { $0.projected > $1.projected }
        next.captain = evaluation.captain
        next.viceCaptain = evaluation.starting
            .filter { $0.id != evaluation.captain.id }
            .max(by: { $0.projected < $1.projected }) ?? evaluation.captain
        return rebuilt(next)
    }

    // MARK: - Recompute derived values

    /// Re-derives cost, formation, projected points and armband validity after
    /// any change to the 15.
    static func rebuilt(_ squad: OptimizedSquad) -> OptimizedSquad {
        var next = squad
        next.starting = squad.starting.sorted { lhs, rhs in
            lhs.position.rawValue == rhs.position.rawValue
                ? lhs.projected > rhs.projected
                : lhs.position.rawValue < rhs.position.rawValue
        }
        next.totalCostTenths = squad.squad.reduce(0) { $0 + $1.priceTenths }

        if !next.starting.contains(where: { $0.id == next.captain.id }) {
            next.captain = next.starting.max(by: { $0.projected < $1.projected }) ?? next.captain
        }
        if !next.starting.contains(where: { $0.id == next.viceCaptain.id })
            || next.viceCaptain.id == next.captain.id {
            next.viceCaptain = next.starting
                .filter { $0.id != next.captain.id }
                .max(by: { $0.projected < $1.projected }) ?? next.captain
        }

        let defenders = next.starting.filter { $0.position == .defender }.count
        let midfielders = next.starting.filter { $0.position == .midfielder }.count
        let forwards = next.starting.filter { $0.position == .forward }.count
        next.formation = "\(defenders)-\(midfielders)-\(forwards)"
        next.projectedPoints = next.starting.reduce(0) { $0 + $1.projected } + next.captain.projected
        return next
    }

    // MARK: - Rebuilding a saved team

    static func squad(from saved: SavedTeam, rated: [RatedPlayer]) throws -> OptimizedSquad {
        let byID = Dictionary(uniqueKeysWithValues: rated.map { ($0.id, $0) })
        let players = saved.playerIDs.compactMap { byID[$0] }
        guard players.count == saved.playerIDs.count else {
            throw SquadEditError.missingPlayers(saved.playerIDs.count - players.count)
        }
        var starting = saved.startingIDs.compactMap { byID[$0] }
        var bench = saved.benchIDs.compactMap { byID[$0] }
        if !isLegalStartingEleven(starting) {
            // Formation rules changed under us (or the file was hand-edited).
            let evaluation = SquadOptimizer.evaluate(players)
            starting = evaluation.starting
            bench = evaluation.bench
        }
        let captain = byID[saved.captainID] ?? starting[0]
        let vice = byID[saved.viceCaptainID] ?? starting[0]

        let squad = OptimizedSquad(
            squad: players,
            starting: starting,
            bench: bench.filter { $0.position == .goalkeeper } + bench.filter { $0.position != .goalkeeper },
            captain: captain,
            viceCaptain: vice,
            formation: saved.formation,
            totalCostTenths: players.reduce(0) { $0 + $1.priceTenths },
            budgetTenths: saved.budgetTenths,
            projectedPoints: 0,
            notes: ["Loaded from “\(saved.name)” — prices and projections are today's."],
            edited: true
        )
        return rebuilt(squad)
    }
}
