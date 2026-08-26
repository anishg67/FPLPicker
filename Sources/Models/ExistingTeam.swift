import Foundation

/// Whether the user already has a squad in the real game, and how they want to
/// tell us about it. Decided by the survey's first question.
enum TeamStatus: String, Codable, CaseIterable, Identifiable {
    case none          // start from scratch
    case importByID    // fetch it from FPL with a team ID
    case manual        // type the 15 in by hand

    var id: String { rawValue }
    var hasTeam: Bool { self != .none }

    var title: String {
        switch self {
        case .none: return "I'm starting from scratch"
        case .importByID: return "Import it with my team ID"
        case .manual: return "I'll enter my 15 by hand"
        }
    }
    var detail: String {
        switch self {
        case .none: return "Build me a whole squad from nothing"
        case .importByID: return "Pull my current squad, bank and value straight from the game"
        case .manual: return "Pick my players, then tell you my bank and free transfers"
        }
    }
}

/// A squad the user already owns, plus the resources they have to change it.
struct ExistingTeam: Codable, Equatable {
    var playerIDs: [Int] = []
    var bankTenths: Int = 0
    var freeTransfers: Int = 1
    var entryID: Int?
    var teamName: String?
    var managerName: String?
    /// Squad value reported by FPL, when the team came from the API.
    var reportedValueTenths: Int?

    var isComplete: Bool { playerIDs.count == 15 }
}

/// What the user still has to fix before a hand-entered squad is usable.
struct SquadValidation {
    var missing: [Position: Int] = [:]
    var overClubLimit: [String] = []

    var isValid: Bool { missing.isEmpty && overClubLimit.isEmpty }

    var message: String? {
        var parts: [String] = []
        let ordered = Position.allCases.compactMap { position -> String? in
            guard let count = missing[position], count > 0 else { return nil }
            return "\(count) more \(position.short)"
        }
        if !ordered.isEmpty { parts.append("Still need \(ordered.joined(separator: ", "))") }
        for club in overClubLimit { parts.append("More than 3 players from \(club)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func check(_ players: [RatedPlayer], maxPerClub: Int = 3) -> SquadValidation {
        var validation = SquadValidation()
        for position in Position.allCases {
            let have = players.filter { $0.position == position }.count
            if have < position.squadCount {
                validation.missing[position] = position.squadCount - have
            }
        }
        var counts: [Int: Int] = [:]
        for player in players { counts[player.element.team, default: 0] += 1 }
        for (team, count) in counts where count > maxPerClub {
            if let name = players.first(where: { $0.element.team == team })?.team.name {
                validation.overClubLimit.append(name)
            }
        }
        return validation
    }
}
