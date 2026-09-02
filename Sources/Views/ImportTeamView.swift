import SwiftUI

/// Where the user tells the app about a squad they already own — either by FPL
/// team ID or by picking the 15 players by hand — along with their bank and free
/// transfers.
struct ImportTeamView: View {
    @EnvironmentObject var state: AppState

    @State private var method: TeamStatus = .importByID
    @State private var idText = ""
    @State private var draft = ExistingTeam()
    @State private var pickingPosition: Position?
    @State private var showingGlossary = false

    private var chosen: [RatedPlayer] { state.players(ids: draft.playerIDs) }
    private var validation: SquadValidation { SquadValidation.check(chosen) }
    private var squadCostTenths: Int { chosen.reduce(0) { $0 + $1.priceTenths } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    methodPicker

                    if method == .importByID {
                        idCard
                    } else {
                        squadBuilder
                    }

                    if !draft.playerIDs.isEmpty { resourcesCard }

                    if let error = state.importError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.35)))
                    }

                    if let message = validation.message, !draft.playerIDs.isEmpty {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.yellow)
                    }

                    Button("Use this team") {
                        state.useExistingTeam(draft)
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: canContinue))
                    .disabled(!canContinue)

                    Button("Skip — build me a new squad instead") {
                        state.importError = nil
                        state.phase = .preferences
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
                .readableColumn()
            }
        }
        .sheet(item: $pickingPosition) { position in
            SquadSlotPickerView(position: position, selected: draft.playerIDs) { player in
                draft.playerIDs.append(player.id)
            }
            .environmentObject(state)
        }
        .sheet(isPresented: $showingGlossary) { GlossaryView() }
        .onAppear {
            if let status = state.survey?.teamStatus, status.hasTeam { method = status }
            if let existing = state.importedTeam ?? state.lastImportDraft { draft = existing }
        }
    }

    private var canContinue: Bool { draft.isComplete && validation.isValid }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your current team")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Tell me what you already own and I'll suggest the transfers worth making — inside your bank and free transfers.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingGlossary = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                    Text("What's a free transfer? A hit?")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.mint)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Capsule().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }

    private var methodPicker: some View {
        Picker("", selection: $method) {
            Text("Team ID").tag(TeamStatus.importByID)
            Text("Pick by hand").tag(TeamStatus.manual)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Import by ID

    private var idCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your team ID").font(.headline).foregroundStyle(.white)
            Text("Your team number is in the address, like fantasy.premierleague.com/entry/**1234567**/event/2. Here's how to find it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                linkStep(1, prefix: "Log in to your account at",
                         linkText: "fantasy.premierleague.com",
                         url: URL(string: "https://fantasy.premierleague.com")!)
                step(2, "Open the **Pick Team** tab")
                step(3, "Read the team number out of the address bar, like **1234567**")
            }
            .padding(.vertical, 2)

            HStack(spacing: 10) {
                TextField("1234567", text: $idText)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))

                Button {
                    Task {
                        guard let id = Int(idText.trimmingCharacters(in: .whitespaces)) else { return }
                        if let team = await state.fetchTeam(id: id) {
                            draft = team
                        }
                    }
                } label: {
                    if state.isImporting {
                        ProgressView().tint(Theme.deepPurple).frame(width: 70)
                    } else {
                        Text("Find")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 70)
                    }
                }
                .padding(.vertical, 14)
                .background(Capsule().fill(Theme.accentGradient))
                .foregroundStyle(Theme.deepPurple)
                .disabled(Int(idText) == nil || state.isImporting)
            }

            if let name = draft.teamName {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    if let manager = draft.managerName {
                        Text(manager).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Text("\(draft.playerIDs.count) players · \(formatPrice(tenths: draft.bankTenths)) in the bank")
                        .font(.caption)
                        .foregroundStyle(Theme.mint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
            }

            Text("Before the season kicks off, squads aren't published, so importing only works once gameweek 1 has started. Pick by hand until then.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func stepNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.deepPurple)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Theme.mint))
    }

    /// One numbered instruction, with the number in a filled circle.
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stepNumber(number)
            Text(.init(text))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// A numbered instruction whose address opens in the browser. Uses a Link
    /// rather than a markdown link inside Text: the latter renders as tinted
    /// text but doesn't reliably respond to a tap.
    private func linkStep(_ number: Int, prefix: String, linkText: String, url: URL) -> some View {
        HStack(alignment: .top, spacing: 10) {
            stepNumber(number)
            VStack(alignment: .leading, spacing: 3) {
                Text(prefix)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(linkText)
                            .font(.caption.weight(.semibold))
                            .underline()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.mint)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Manual squad builder

    private var squadBuilder: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your 15").font(.headline).foregroundStyle(.white)
                Spacer()
                Text("\(draft.playerIDs.count)/15")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(draft.isComplete ? Theme.mint : .white.opacity(0.6))
                if !draft.playerIDs.isEmpty {
                    Button("Clear") { draft.playerIDs = [] }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mint)
                }
            }

            ForEach(Position.allCases) { position in
                let players = chosen.filter { $0.position == position }
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(position.name.uppercased())S — \(players.count)/\(position.squadCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.mint)

                    ForEach(players) { player in
                        HStack {
                            PlayerRow(player: player)
                            Button {
                                draft.playerIDs.removeAll { $0 == player.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }

                    if players.count < position.squadCount {
                        Button {
                            pickingPosition = position
                        } label: {
                            Label("Add \(position.name.lowercased())", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.mint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !chosen.isEmpty {
                Text("Squad value \(formatPrice(tenths: squadCostTenths)) at today's prices.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .card()
    }

    // MARK: - Bank and free transfers

    private var resourcesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $draft.bankTenths, in: 0...500) {
                    HStack {
                        Text("In the bank").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(formatPrice(tenths: draft.bankTenths))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.mint)
                    }
                }
                .tint(Theme.mint)
                Text("Money you haven't spent. It sets how far you can upgrade.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $draft.freeTransfers, in: 0...5) {
                    HStack {
                        Text("Free transfers").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(draft.freeTransfers)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.mint)
                    }
                }
                .tint(Theme.mint)
                Text("Swaps you can make without paying 4 points. It isn't published anywhere, so check your own team and set it here.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
        .card()
    }
}

/// Player list filtered to one position, for filling a squad slot by hand.
struct SquadSlotPickerView: View {
    let position: Position
    let selected: [Int]
    let onPick: (RatedPlayer) -> Void

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var clubCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for player in state.players(ids: selected) { counts[player.element.team, default: 0] += 1 }
        return counts
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                List {
                    ForEach(state.searchPlayers(query, position: position).prefix(150)) { player in
                        let taken = selected.contains(player.id)
                        let clubFull = clubCounts[player.element.team, default: 0] >= 3
                        Button {
                            onPick(player)
                            dismiss()
                        } label: {
                            HStack {
                                PlayerRow(player: player)
                                if taken {
                                    Text("PICKED").font(.caption2.weight(.bold)).foregroundStyle(Theme.mint)
                                } else if clubFull {
                                    Text("3 from this club")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .opacity(taken || clubFull ? 0.45 : 1)
                        }
                        .disabled(taken || clubFull)
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .searchable(text: $query, prompt: "Search \(position.name.lowercased())s")
            .navigationTitle("Add a \(position.name.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.mint)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
