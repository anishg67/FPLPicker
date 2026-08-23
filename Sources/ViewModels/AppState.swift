import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case failed(String)
        case survey
        case importTeam
        case preferences
        case building
        case result
    }

    @Published var phase: Phase = .loading
    @Published var data: LeagueData?
    @Published var prefs: Preferences = Store.loadPreferences() ?? .default
    /// App-wide look and behaviour, separate from any one squad's inputs.
    @Published var settings: AppSettings = Store.loadSettings() ?? .default {
        didSet {
            guard settings != oldValue else { return }
            Theme.accent = settings.accent
            Store.save(settings: settings)
        }
    }
    @Published var survey: SurveyResult? = Store.loadSurvey()
    @Published var squad: OptimizedSquad?
    @Published var rated: [RatedPlayer] = []
    @Published var buildError: String?

    /// Teams the user has kept, newest first.
    @Published var savedTeams: [SavedTeam] = TeamStore.load()
    /// Set when the on-screen squad came from (or was saved to) a stored team.
    @Published var currentTeamID: UUID?
    /// Surfaced as a toast on the squad screen after an illegal edit.
    @Published var editError: String?

    /// Set when the user is working from a squad they already own.
    @Published var importedTeam: ExistingTeam?
    @Published var transferPlan: TransferPlan?
    @Published var transfersMade = 0
    @Published var importError: String?
    @Published var isImporting = false
    /// Last squad the user told us about, kept so they don't have to type their
    /// 15 in again next launch.
    @Published var lastImportDraft: ExistingTeam? = Store.loadExistingTeam()

    private let service = FPLService()

    init() {
        Theme.accent = settings.accent
    }

    /// Preferences with the app-wide defaults folded in.
    var effectivePrefs: Preferences {
        var effective = prefs.effective
        if prefs.mode == .auto { effective.budgetTenths = settings.defaultBudgetTenths }
        return effective
    }

    var dataAgeDescription: String? {
        guard let fetched = data?.fetchedAt else { return nil }
        let minutes = Int(Date().timeIntervalSince(fetched) / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        return "Updated \(minutes / 60)h ago"
    }

    var nextDeadline: String? {
        guard let event = data?.nextEvent, let date = event.deadlineTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, HH:mm"
        return "\(event.name) deadline · \(formatter.string(from: date))"
    }

    // MARK: - Loading

    func start() async {
        phase = .loading
        do {
            let league = try await service.load()
            data = league
            refreshRatings()
            phase = survey == nil ? .survey : .preferences
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func retry() {
        Task { await start() }
    }

    // MARK: - Survey

    func completeSurvey(_ result: SurveyResult, mode: SkillMode) {
        survey = result
        prefs.mode = mode
        Store.save(survey: result)
        Store.save(preferences: prefs)
        phase = result.teamStatus.hasTeam ? .importTeam : .preferences
    }

    func startImport() {
        importError = nil
        phase = .importTeam
    }

    func retakeSurvey() {
        phase = .survey
    }

    // MARK: - Building

    /// Re-scores every player with the current preferences.
    func refreshRatings() {
        guard let data else { return }
        let engine = ProjectionEngine(data: data, prefs: effectivePrefs)
        rated = engine.rateAll()
    }

    func build() {
        guard let data else { return }
        Store.save(preferences: prefs)
        buildError = nil
        phase = .building

        let effective = effectivePrefs
        Task.detached(priority: .userInitiated) {
            let engine = ProjectionEngine(data: data, prefs: effective)
            let rated = engine.rateAll()
            let optimizer = SquadOptimizer(rated: rated, prefs: effective)
            do {
                let result = try optimizer.optimize()
                await MainActor.run {
                    self.rated = rated
                    self.squad = result
                    self.currentTeamID = nil
                    self.importedTeam = nil
                    self.transferPlan = nil
                    self.transfersMade = 0
                    self.phase = .result
                }
            } catch {
                await MainActor.run {
                    self.buildError = error.localizedDescription
                    self.phase = .preferences
                }
            }
        }
    }

    func editPreferences() {
        phase = .preferences
    }

    // MARK: - Working from a team the user already owns

    /// Fetches a real squad from FPL by team ID.
    func fetchTeam(id: Int) async -> ExistingTeam? {
        isImporting = true
        importError = nil
        defer { isImporting = false }
        do {
            return try await service.loadTeam(id: id)
        } catch {
            importError = error.localizedDescription
            return nil
        }
    }

    func players(ids: [Int]) -> [RatedPlayer] {
        let byID = Dictionary(uniqueKeysWithValues: rated.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Turns a squad the user already owns into a working squad, then works out
    /// which transfers would improve it.
    func useExistingTeam(_ team: ExistingTeam) {
        let players = players(ids: team.playerIDs)
        guard players.count == 15 else {
            importError = "\(15 - players.count) of those players aren't in the game any more."
            return
        }
        let validation = SquadValidation.check(players)
        guard validation.isValid else {
            importError = validation.message
            return
        }

        let evaluation = SquadOptimizer.evaluate(players)
        let cost = players.reduce(0) { $0 + $1.priceTenths }
        let vice = SquadOptimizer.bestCaptain(in: evaluation.starting,
                                              excluding: evaluation.captain.id)
            ?? evaluation.captain

        var notes: [String] = []
        if let name = team.teamName { notes.append("Imported from “\(name)”.") }
        notes.append("Working from the 15 you already own, at today's prices.")

        squad = SquadEditor.rebuilt(OptimizedSquad(
            squad: players,
            starting: evaluation.starting,
            bench: evaluation.bench.filter { $0.position == .goalkeeper }
                + evaluation.bench.filter { $0.position != .goalkeeper },
            captain: evaluation.captain,
            viceCaptain: vice,
            formation: evaluation.formation,
            totalCostTenths: cost,
            budgetTenths: cost + team.bankTenths,
            projectedPoints: 0,
            notes: notes
        ))
        importedTeam = team
        lastImportDraft = team
        Store.save(existingTeam: team)
        transfersMade = 0
        currentTeamID = nil
        importError = nil
        editError = nil
        recomputeTransferPlan()
        phase = .result
    }

    var freeTransfersLeft: Int {
        guard let team = importedTeam else { return 0 }
        return max(0, team.freeTransfers - transfersMade)
    }

    func recomputeTransferPlan() {
        guard let squad, importedTeam != nil else {
            transferPlan = nil
            return
        }
        let planner = TransferPlanner(
            squad: squad.squad,
            rated: rated,
            bankTenths: squad.remainingTenths,
            freeTransfers: freeTransfersLeft,
            maxPerClub: effectivePrefs.maxPerClub
        )
        transferPlan = planner.plan()
    }

    func apply(_ move: TransferMove) {
        replace(move.outgoing, with: move.incoming)
    }

    func applySuggestedTransfers() {
        guard let plan = transferPlan else { return }
        for move in plan.moves { replace(move.outgoing, with: move.incoming) }
    }

    func setFreeTransfers(_ count: Int) {
        importedTeam?.freeTransfers = count
        recomputeTransferPlan()
    }

    // MARK: - Manual editing

    private var maxPerClub: Int { effectivePrefs.maxPerClub }

    private func apply(_ change: () throws -> OptimizedSquad) {
        do {
            squad = try change()
            editError = nil
        } catch {
            editError = error.localizedDescription
        }
    }

    func replace(_ outgoing: RatedPlayer, with incoming: RatedPlayer) {
        guard let squad else { return }
        let before = self.squad?.squad.map(\.id)
        apply { try SquadEditor.replace(squad, outgoing: outgoing, incoming: incoming, maxPerClub: maxPerClub) }
        guard importedTeam != nil, self.squad?.squad.map(\.id) != before else { return }
        transfersMade += 1
        recomputeTransferPlan()
    }

    func substitute(starter: RatedPlayer, with sub: RatedPlayer) {
        guard let squad else { return }
        apply { try SquadEditor.substitute(squad, starter: starter, substitute: sub) }
        recomputeTransferPlan()
    }

    func makeCaptain(_ player: RatedPlayer) {
        guard let squad else { return }
        apply { try SquadEditor.setCaptain(squad, player: player) }
    }

    func makeViceCaptain(_ player: RatedPlayer) {
        guard let squad else { return }
        apply { try SquadEditor.setViceCaptain(squad, player: player) }
    }

    func autoPickStartingEleven() {
        guard let squad else { return }
        self.squad = SquadEditor.autoPickStartingEleven(squad)
        editError = nil
    }

    func isStarting(_ player: RatedPlayer) -> Bool {
        squad?.starting.contains(where: { $0.id == player.id }) ?? false
    }

    func substitutionPartners(for player: RatedPlayer) -> [RatedPlayer] {
        guard let squad else { return [] }
        return SquadEditor.legalPartners(for: player, in: squad)
    }

    /// Everyone who could come in for `outgoing`, flagged for affordability and
    /// the three-per-club rule.
    func transferOptions(for outgoing: RatedPlayer, query: String) -> [TransferOption] {
        guard let squad else { return [] }
        let squadIDs = Set(squad.squad.map(\.id))
        let headroom = squad.budgetTenths - squad.totalCostTenths + outgoing.priceTenths
        var clubCounts: [Int: Int] = [:]
        for player in squad.squad { clubCounts[player.element.team, default: 0] += 1 }
        clubCounts[outgoing.element.team, default: 1] -= 1

        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rated
            .filter { candidate in
                guard candidate.position == outgoing.position else { return false }
                guard !squadIDs.contains(candidate.id) else { return false }
                guard !trimmed.isEmpty else { return true }
                return candidate.element.webName.lowercased().contains(trimmed)
                    || candidate.element.fullName.lowercased().contains(trimmed)
                    || candidate.team.name.lowercased().contains(trimmed)
                    || candidate.team.shortName.lowercased().contains(trimmed)
            }
            .sorted { $0.projected > $1.projected }
            .prefix(150)
            .map { candidate in
                TransferOption(
                    player: candidate,
                    affordable: candidate.priceTenths <= headroom,
                    clubBlocked: clubCounts[candidate.element.team, default: 0] >= maxPerClub,
                    priceDelta: candidate.priceTenths - outgoing.priceTenths
                )
            }
    }

    // MARK: - Saving and loading teams

    @discardableResult
    func saveCurrentTeam(name: String) -> Bool {
        guard let squad else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = SavedTeam(squad: squad,
                             name: trimmed.isEmpty ? defaultTeamName : trimmed,
                             gameweek: data?.nextEvent?.name)
        savedTeams.insert(team, at: 0)
        currentTeamID = team.id
        TeamStore.save(savedTeams)
        return true
    }

    func updateCurrentTeam() {
        guard let squad, let id = currentTeamID,
              let index = savedTeams.firstIndex(where: { $0.id == id }) else { return }
        var team = SavedTeam(squad: squad, name: savedTeams[index].name, gameweek: data?.nextEvent?.name)
        team.id = id
        savedTeams[index] = team
        savedTeams.sort { $0.savedAt > $1.savedAt }
        TeamStore.save(savedTeams)
    }

    func delete(_ team: SavedTeam) {
        savedTeams.removeAll { $0.id == team.id }
        if currentTeamID == team.id { currentTeamID = nil }
        TeamStore.save(savedTeams)
    }

    func rename(_ team: SavedTeam, to name: String) {
        guard let index = savedTeams.firstIndex(where: { $0.id == team.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedTeams[index].name = trimmed
        TeamStore.save(savedTeams)
    }

    func load(_ team: SavedTeam) {
        guard !rated.isEmpty else { return }
        do {
            let rebuilt = try SquadEditor.squad(from: team, rated: rated)
            squad = rebuilt
            currentTeamID = team.id
            // Treat it as a squad the user owns, so transfer suggestions work
            // the same way they do for an imported team.
            importedTeam = ExistingTeam(
                playerIDs: rebuilt.squad.map(\.id),
                bankTenths: rebuilt.remainingTenths,
                freeTransfers: importedTeam?.freeTransfers ?? 1,
                teamName: team.name
            )
            transfersMade = 0
            editError = nil
            recomputeTransferPlan()
            phase = .result
        } catch {
            editError = error.localizedDescription
        }
    }

    var currentTeamName: String? {
        guard let id = currentTeamID else { return nil }
        return savedTeams.first(where: { $0.id == id })?.name
    }

    var defaultTeamName: String {
        let gameweek = data?.nextEvent?.name ?? "My"
        return "\(gameweek) squad"
    }

    // MARK: - Settings actions

    /// Re-fetches prices, form and fixtures without touching the current squad.
    func refreshData() async {
        do {
            let league = try await service.load()
            data = league
            refreshRatings()
            if let current = squad {
                // Re-price the same 15 with the new data.
                let byID = Dictionary(uniqueKeysWithValues: rated.map { ($0.id, $0) })
                let players = current.squad.compactMap { byID[$0.id] }
                if players.count == 15 {
                    var updated = current
                    updated.squad = players
                    updated.starting = current.starting.compactMap { byID[$0.id] }
                    updated.bench = current.bench.compactMap { byID[$0.id] }
                    if let captain = byID[current.captain.id] { updated.captain = captain }
                    if let vice = byID[current.viceCaptain.id] { updated.viceCaptain = vice }
                    squad = SquadEditor.rebuilt(updated)
                    recomputeTransferPlan()
                }
            }
        } catch {
            editError = error.localizedDescription
        }
    }

    func deleteAllSavedTeams() {
        savedTeams.removeAll()
        currentTeamID = nil
        TeamStore.save(savedTeams)
    }

    func forgetImportedTeam() {
        importedTeam = nil
        lastImportDraft = nil
        transferPlan = nil
        transfersMade = 0
        Store.clearExistingTeam()
    }

    /// Wipes everything the app remembers and starts the survey again.
    func resetEverything() {
        Store.reset()
        deleteAllSavedTeams()
        prefs = .default
        settings = .default
        survey = nil
        squad = nil
        importedTeam = nil
        lastImportDraft = nil
        transferPlan = nil
        transfersMade = 0
        currentTeamID = nil
        refreshRatings()
        phase = .survey
    }

    // MARK: - Player lookup helpers (expert mode pickers)

    func player(id: Int) -> RatedPlayer? { rated.first(where: { $0.id == id }) }

    func searchPlayers(_ query: String, position: Position?) -> [RatedPlayer] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        return rated
            .filter { player in
                if let position, player.position != position { return false }
                guard !trimmed.isEmpty else { return true }
                return player.element.webName.lowercased().contains(trimmed)
                    || player.element.fullName.lowercased().contains(trimmed)
                    || player.team.name.lowercased().contains(trimmed)
            }
            .sorted { $0.projected > $1.projected }
    }
}

/// A possible incoming player for a transfer, with the reasons it may be blocked.
struct TransferOption: Identifiable {
    let player: RatedPlayer
    let affordable: Bool
    let clubBlocked: Bool
    let priceDelta: Int          // positive means it costs more than the outgoing player

    var id: Int { player.id }
    var selectable: Bool { affordable && !clubBlocked }
    var blockReason: String? {
        if clubBlocked { return "3 from this club" }
        if !affordable { return "Too expensive" }
        return nil
    }
    var deltaLabel: String {
        priceDelta == 0 ? "same price"
            : (priceDelta > 0 ? "+\(formatPrice(tenths: priceDelta))" : "−\(formatPrice(tenths: -priceDelta))")
    }
}

/// Small UserDefaults-backed store for the survey answer and preferences.
enum Store {
    private static let surveyKey = "fplpicker.survey"
    private static let prefsKey = "fplpicker.preferences"

    static func save(survey: SurveyResult) {
        if let data = try? JSONEncoder().encode(survey) {
            UserDefaults.standard.set(data, forKey: surveyKey)
        }
    }

    static func loadSurvey() -> SurveyResult? {
        guard let data = UserDefaults.standard.data(forKey: surveyKey) else { return nil }
        return try? JSONDecoder().decode(SurveyResult.self, from: data)
    }

    static func save(preferences: Preferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }

    static func loadPreferences() -> Preferences? {
        guard let data = UserDefaults.standard.data(forKey: prefsKey) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: data)
    }

    private static let settingsKey = "fplpicker.settings"
    private static let existingTeamKey = "fplpicker.existingTeam"

    static func save(settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    static func loadSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    static func clearExistingTeam() {
        UserDefaults.standard.removeObject(forKey: existingTeamKey)
    }

    static func save(existingTeam: ExistingTeam) {
        if let data = try? JSONEncoder().encode(existingTeam) {
            UserDefaults.standard.set(data, forKey: existingTeamKey)
        }
    }

    static func loadExistingTeam() -> ExistingTeam? {
        guard let data = UserDefaults.standard.data(forKey: existingTeamKey) else { return nil }
        return try? JSONDecoder().decode(ExistingTeam.self, from: data)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: surveyKey)
        UserDefaults.standard.removeObject(forKey: prefsKey)
        UserDefaults.standard.removeObject(forKey: existingTeamKey)
        UserDefaults.standard.removeObject(forKey: settingsKey)
    }
}
