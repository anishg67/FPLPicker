import Foundation

/// How much of the decision-making the user wants to keep. Decided by the
/// onboarding survey, overridable at any time.
enum SkillMode: String, Codable, CaseIterable, Identifiable {
    case auto, guided, expert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Do It For Me"
        case .guided: return "Guided"
        case .expert: return "Full Control"
        }
    }
    var blurb: String {
        switch self {
        case .auto:
            return "You tell me nothing. I pick a full legal squad, starting XI and captain using live prices, form and fixtures."
        case .guided:
            return "You set your budget and the clubs you want players from. I handle the rest."
        case .expert:
            return "Every dial: risk appetite, fixture horizon, form weighting, club caps, must-haves and blocklist."
        }
    }
    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .guided: return "slider.horizontal.3"
        case .expert: return "dial.max"
        }
    }
}

/// Whether preferred clubs are a hard filter or a soft nudge.
enum TeamPreferenceMode: String, Codable, CaseIterable, Identifiable {
    case bias, only
    var id: String { rawValue }
    var title: String { self == .bias ? "Favour them" : "Only these clubs" }
    var detail: String {
        self == .bias
            ? "Players from these clubs get a boost, but I can still pick elsewhere."
            : "Every one of the 15 must come from these clubs (pick at least 5)."
    }
}

struct Preferences: Codable, Equatable {
    var mode: SkillMode = .auto

    // Guided + expert
    var budgetTenths: Int = 1000              // £100.0m, the FPL default
    var preferredTeams: Set<Int> = []
    var teamMode: TeamPreferenceMode = .bias

    // Expert only
    var maxPerClub: Int = 3                   // FPL hard limit is 3
    var riskAppetite: Double = 0.0            // -1 template ... +1 differential
    var fixtureHorizon: Int = 5               // gameweeks of fixtures to weigh
    var formWeight: Double = 0.35             // recent form vs season-long output
    var avoidInjuryRisk: Bool = true
    var mustInclude: Set<Int> = []
    var exclude: Set<Int> = []

    static let `default` = Preferences()

    /// Expert dials collapse to sane defaults for the simpler modes.
    var effective: Preferences {
        switch mode {
        case .auto:
            var p = Preferences.default
            p.mode = .auto
            return p
        case .guided:
            var p = Preferences.default
            p.mode = .guided
            p.budgetTenths = budgetTenths
            p.preferredTeams = preferredTeams
            p.teamMode = teamMode
            return p
        case .expert:
            return self
        }
    }
}

/// Result of the onboarding survey.
struct SurveyResult: Codable, Equatable {
    var knowledge: Int          // 0...100
    var recommended: SkillMode
    var teamStatus: TeamStatus = .none

    init(knowledge: Int, recommended: SkillMode, teamStatus: TeamStatus = .none) {
        self.knowledge = knowledge
        self.recommended = recommended
        self.teamStatus = teamStatus
    }

    // Hand-written so surveys saved before the team question still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        knowledge = try container.decode(Int.self, forKey: .knowledge)
        recommended = try container.decode(SkillMode.self, forKey: .recommended)
        teamStatus = try container.decodeIfPresent(TeamStatus.self, forKey: .teamStatus) ?? .none
    }

    var label: String {
        switch knowledge {
        case ..<30: return "New to this"
        case ..<65: return "Casual fan"
        default: return "Seasoned manager"
        }
    }
}
