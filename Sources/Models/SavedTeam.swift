import Foundation

/// A squad the user has kept. Only IDs are stored — prices, form and fixtures
/// are re-read from the live API when the team is loaded again.
struct SavedTeam: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var savedAt: Date
    var playerIDs: [Int]
    var startingIDs: [Int]
    var benchIDs: [Int]
    var captainID: Int
    var viceCaptainID: Int
    var budgetTenths: Int
    var formation: String
    var gameweek: String?

    var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        return "\(formation) · saved \(formatter.string(from: savedAt))"
    }
}

/// JSON file in Documents. Small enough that load/save on the main actor is fine.
enum TeamStore {
    private static var url: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("saved-teams.json")
    }

    static func load() -> [SavedTeam] {
        guard let data = try? Data(contentsOf: url),
              let teams = try? JSONDecoder().decode([SavedTeam].self, from: data)
        else { return [] }
        return teams.sorted { $0.savedAt > $1.savedAt }
    }

    static func save(_ teams: [SavedTeam]) {
        guard let data = try? JSONEncoder().encode(teams) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

extension SavedTeam {
    init(squad: OptimizedSquad, name: String, gameweek: String?) {
        self.init(
            name: name,
            savedAt: Date(),
            playerIDs: squad.squad.map(\.id),
            startingIDs: squad.starting.map(\.id),
            benchIDs: squad.bench.map(\.id),
            captainID: squad.captain.id,
            viceCaptainID: squad.viceCaptain.id,
            budgetTenths: squad.budgetTenths,
            formation: squad.formation,
            gameweek: gameweek
        )
    }
}
