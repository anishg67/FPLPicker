import Foundation

// MARK: - Raw API shapes (fantasy.premierleague.com/api)

/// Everything the game exposes in one payload: players, clubs, gameweeks.
struct Bootstrap: Decodable {
    let events: [GameweekEvent]
    let teams: [FPLTeam]
    let elements: [Element]
    let elementTypes: [ElementType]
}

struct GameweekEvent: Decodable {
    let id: Int
    let name: String
    let deadlineTime: Date?
    let finished: Bool
    let isNext: Bool
    let isCurrent: Bool
}

struct FPLTeam: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let shortName: String
    let strength: Int?
}

struct ElementType: Decodable, Identifiable {
    let id: Int
    let singularNameShort: String
    let squadSelect: Int
    let squadMinPlay: Int
    let squadMaxPlay: Int
}

/// A player. The API sends most rate stats as strings, so those are kept as
/// optional strings and surfaced through `num(_:)`.
struct Element: Decodable, Identifiable, Hashable {
    let id: Int
    let code: Int
    let webName: String
    let firstName: String
    let secondName: String
    let team: Int
    let elementType: Int
    let nowCost: Int          // tenths of a million: 60 == £6.0m
    let totalPoints: Int
    let minutes: Int
    let starts: Int
    let bonus: Int
    let goalsScored: Int
    let assists: Int
    let cleanSheets: Int
    let saves: Int
    let status: String        // a=available d=doubtful i=injured s=suspended u/n=unavailable
    let news: String
    let chanceOfPlayingNextRound: Int?
    let penaltiesOrder: Int?

    // The API is inconsistent about these: some arrive as strings ("4.4"),
    // some as raw numbers. LooseDouble accepts either.
    let form: LooseDouble
    let pointsPerGame: LooseDouble
    let epNext: LooseDouble
    let selectedByPercent: LooseDouble
    let ictIndex: LooseDouble
    let expectedGoalsPer90: LooseDouble
    let expectedAssistsPer90: LooseDouble
    let expectedGoalInvolvementsPer90: LooseDouble
    let expectedGoalsConcededPer90: LooseDouble
    let savesPer90: LooseDouble
    let cleanSheetsPer90: LooseDouble
    let defensiveContributionPer90: LooseDouble
    let startsPer90: LooseDouble

    static func == (lhs: Element, rhs: Element) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A numeric stat that the FPL API may send as a string, a number, or null.
struct LooseDouble: Decodable, Hashable {
    let value: Double
    let isPresent: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = 0
            isPresent = false
        } else if let number = try? container.decode(Double.self) {
            value = number
            isPresent = true
        } else if let text = try? container.decode(String.self) {
            value = Double(text) ?? 0
            isPresent = Double(text) != nil
        } else {
            value = 0
            isPresent = false
        }
    }

    init(_ value: Double) {
        self.value = value
        self.isPresent = true
    }

    /// Display form: "—" when the stat is missing.
    func text(_ format: String = "%.1f") -> String {
        isPresent ? String(format: format, value) : "—"
    }
}

struct Fixture: Decodable {
    let id: Int
    let event: Int?
    let teamH: Int
    let teamA: Int
    let teamHDifficulty: Int
    let teamADifficulty: Int
    let finished: Bool
    let kickoffTime: Date?
}

// MARK: - Domain conveniences

enum Position: Int, CaseIterable, Identifiable, Codable {
    case goalkeeper = 1, defender = 2, midfielder = 3, forward = 4

    var id: Int { rawValue }
    var short: String {
        switch self {
        case .goalkeeper: return "GKP"
        case .defender: return "DEF"
        case .midfielder: return "MID"
        case .forward: return "FWD"
        }
    }
    var name: String {
        switch self {
        case .goalkeeper: return "Goalkeeper"
        case .defender: return "Defender"
        case .midfielder: return "Midfielder"
        case .forward: return "Forward"
        }
    }
    /// How many of this position a legal 15-man squad must contain.
    var squadCount: Int {
        switch self {
        case .goalkeeper: return 2
        case .defender, .midfielder: return 5
        case .forward: return 3
        }
    }
    /// Legal range for the starting XI.
    var startingRange: ClosedRange<Int> {
        switch self {
        case .goalkeeper: return 1...1
        case .defender: return 3...5
        case .midfielder: return 2...5
        case .forward: return 1...3
        }
    }
}

enum Availability {
    case available, doubtful(Int), out

    var multiplier: Double {
        switch self {
        case .available: return 1.0
        case .doubtful(let chance): return max(0.15, Double(chance) / 100.0)
        case .out: return 0.03
        }
    }
    var label: String? {
        switch self {
        case .available: return nil
        case .doubtful(let chance): return "\(chance)% fit"
        case .out: return "Unavailable"
        }
    }
}

extension Element {
    var position: Position { Position(rawValue: elementType) ?? .midfielder }
    var priceTenths: Int { nowCost }
    var price: Double { Double(nowCost) / 10.0 }
    var fullName: String { "\(firstName) \(secondName)" }
    var ownership: Double { selectedByPercent.value }

    var availability: Availability {
        switch status {
        case "a": return .available
        case "d": return .doubtful(chanceOfPlayingNextRound ?? 50)
        default:
            if let chance = chanceOfPlayingNextRound, chance > 0 { return .doubtful(chance) }
            return .out
        }
    }

    var photoURL: URL? {
        URL(string: "https://resources.premierleague.com/premierleague/photos/players/110x140/p\(code).png")
    }
}

/// Price formatting used everywhere in the UI.
func formatPrice(tenths: Int) -> String {
    String(format: "£%.1fm", Double(tenths) / 10.0)
}
