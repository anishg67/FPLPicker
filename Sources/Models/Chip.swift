import Foundation

/// The four chips the game gives you. Raw values match the API's own names.
enum Chip: String, Codable, CaseIterable, Identifiable {
    case benchBoost = "bboost"
    case tripleCaptain = "3xc"
    case freeHit = "freehit"
    case wildcard = "wildcard"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .benchBoost: return "Bench Boost"
        case .tripleCaptain: return "Triple Captain"
        case .freeHit: return "Free Hit"
        case .wildcard: return "Wildcard"
        }
    }

    var icon: String {
        switch self {
        case .benchBoost: return "rectangle.stack.badge.plus"
        case .tripleCaptain: return "star.circle.fill"
        case .freeHit: return "bolt.horizontal.circle"
        case .wildcard: return "arrow.triangle.2.circlepath"
        }
    }

    var summary: String {
        switch self {
        case .benchBoost:
            return "Your four bench players score as well as your XI, for one gameweek."
        case .tripleCaptain:
            return "Your captain scores triple instead of double, for one gameweek."
        case .freeHit:
            return "Unlimited transfers for one gameweek. Your squad reverts afterwards."
        case .wildcard:
            return "Unlimited transfers that you keep. Rebuild the squad without taking hits."
        }
    }

    /// What makes each chip worth playing, in one line.
    var idealCondition: String {
        switch self {
        case .benchBoost:
            return "Best when all 15 have fixtures — ideally a double gameweek."
        case .tripleCaptain:
            return "Best on a premium with two fixtures, or one very kind one."
        case .freeHit:
            return "Best in a blank gameweek, when much of your squad isn't playing."
        case .wildcard:
            return "Best when your squad has drifted far from the best available one."
        }
    }

    /// How much better than an ordinary week this chip needs to be before it
    /// beats holding on to it.
    ///
    /// Deliberately a multiple rather than a points total. Early in a season the
    /// game's own expected-points figures are just season averages, so every
    /// projection — ours and FPL's alike — runs high; a fixed "worth 14 points"
    /// bar would fire every week. Asking whether *this* week is unusually good
    /// for the chip is both scale-free and how the decision is actually made.
    var playMultiple: Double {
        switch self {
        case .benchBoost: return 1.40    // bench roughly half as good again
        case .tripleCaptain: return 1.25 // a standout captain week
        case .freeHit: return 1.35
        case .wildcard: return 1.08      // squad 8% off the best available
        }
    }
}

/// One chip's availability window, as published by the game. Chips come in
/// halves: one set expires at gameweek 19, the second runs to the end.
struct ChipWindow: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let startEvent: Int
    let stopEvent: Int
    let chipType: String

    var chip: Chip? { Chip(rawValue: name) }
    var isSecondHalf: Bool { startEvent >= 20 }

    func covers(_ gameweek: Int) -> Bool {
        gameweek >= startEvent && gameweek <= stopEvent
    }
}

/// Which chips the user has already played. Each chip exists twice a season,
/// so both halves are tracked separately.
struct ChipUsage: Codable, Equatable {
    var usedFirstHalf: Set<String> = []
    var usedSecondHalf: Set<String> = []

    func hasUsed(_ chip: Chip, secondHalf: Bool) -> Bool {
        secondHalf ? usedSecondHalf.contains(chip.rawValue) : usedFirstHalf.contains(chip.rawValue)
    }

    mutating func toggle(_ chip: Chip, secondHalf: Bool) {
        if secondHalf {
            if usedSecondHalf.contains(chip.rawValue) { usedSecondHalf.remove(chip.rawValue) }
            else { usedSecondHalf.insert(chip.rawValue) }
        } else {
            if usedFirstHalf.contains(chip.rawValue) { usedFirstHalf.remove(chip.rawValue) }
            else { usedFirstHalf.insert(chip.rawValue) }
        }
    }

    var isEmpty: Bool { usedFirstHalf.isEmpty && usedSecondHalf.isEmpty }
    var count: Int { usedFirstHalf.count + usedSecondHalf.count }
}
