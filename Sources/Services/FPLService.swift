import Foundation

/// Everything the engine needs, fetched from the live FPL endpoints.
struct LeagueData {
    let elements: [Element]
    let teams: [FPLTeam]
    let fixtures: [Fixture]
    let nextEvent: GameweekEvent?
    let fetchedAt: Date

    var teamsByID: [Int: FPLTeam] { Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) }) }
}

enum FPLServiceError: LocalizedError {
    case badStatus(Int)
    case transport(String)
    case unknownTeamID(Int)
    case seasonNotStarted

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "The data server replied with status \(code)."
        case .transport(let message):
            return message
        case .unknownTeamID(let id):
            return "No team was found with the ID \(id). It's the number in the address bar when you view your own team on the web."
        case .seasonNotStarted:
            return "The season hasn't kicked off yet, so squads aren't published yet. Enter your 15 by hand instead — it takes a minute."
        }
    }
}

/// The public profile behind a team ID.
struct EntrySummary: Decodable {
    let id: Int
    let name: String
    let playerFirstName: String
    let playerLastName: String
    let currentEvent: Int?
    let lastDeadlineBank: Int?
    let lastDeadlineValue: Int?

    var managerName: String { "\(playerFirstName) \(playerLastName)" }
}

/// One gameweek's picks for a team.
struct PicksResponse: Decodable {
    struct Pick: Decodable {
        let element: Int
        let position: Int
        let isCaptain: Bool
        let isViceCaptain: Bool
    }
    struct History: Decodable {
        let bank: Int
        let value: Int
        let eventTransfers: Int
    }
    let picks: [Pick]
    let entryHistory: History
}

/// Thin client over the public (unauthenticated) FPL JSON API.
struct FPLService {
    static let bootstrapURL = URL(string: "https://fantasy.premierleague.com/api/bootstrap-static/")!
    static let fixturesURL = URL(string: "https://fantasy.premierleague.com/api/fixtures/")!

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadRevalidatingCacheData
        session = URLSession(configuration: config)
    }

    func load() async throws -> LeagueData {
        async let bootstrap: Bootstrap = fetch(Self.bootstrapURL)
        async let fixtures: [Fixture] = fetch(Self.fixturesURL)
        let (boot, fix) = try await (bootstrap, fixtures)

        let next = boot.events.first(where: { $0.isNext })
            ?? boot.events.first(where: { $0.isCurrent })
            ?? boot.events.first(where: { !$0.finished })

        return LeagueData(
            elements: boot.elements,
            teams: boot.teams,
            fixtures: fix,
            nextEvent: next,
            fetchedAt: Date()
        )
    }

    /// Pulls a real team by its FPL ID: the squad, what's in the bank and who
    /// wore the armband last week.
    func loadTeam(id: Int) async throws -> ExistingTeam {
        guard let entryURL = URL(string: "https://fantasy.premierleague.com/api/entry/\(id)/") else {
            throw FPLServiceError.unknownTeamID(id)
        }
        let entry: EntrySummary
        do {
            entry = try await fetch(entryURL)
        } catch FPLServiceError.badStatus(let code) where code == 404 {
            throw FPLServiceError.unknownTeamID(id)
        }

        guard let event = entry.currentEvent else { throw FPLServiceError.seasonNotStarted }
        guard let picksURL = URL(string: "https://fantasy.premierleague.com/api/entry/\(id)/event/\(event)/picks/") else {
            throw FPLServiceError.seasonNotStarted
        }
        let picks: PicksResponse
        do {
            picks = try await fetch(picksURL)
        } catch FPLServiceError.badStatus(let code) where code == 404 {
            throw FPLServiceError.seasonNotStarted
        }

        return ExistingTeam(
            playerIDs: picks.picks.map(\.element),
            bankTenths: picks.entryHistory.bank,
            // FPL doesn't publish how many transfers you have saved, so start
            // from one and let the user correct it.
            freeTransfers: 1,
            entryID: entry.id,
            teamName: entry.name,
            managerName: entry.managerName,
            reportedValueTenths: picks.entryHistory.value
        )
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        // The endpoint 403s requests without a browser-ish user agent.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw FPLServiceError.badStatus(http.statusCode)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch let error as FPLServiceError {
            throw error
        } catch let error as DecodingError {
            throw FPLServiceError.transport("Couldn't read the player data: \(error)")
        } catch {
            throw FPLServiceError.transport(error.localizedDescription)
        }
    }
}
