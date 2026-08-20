import SwiftUI

struct SquadView: View {
    @EnvironmentObject var state: AppState
    let squad: OptimizedSquad

    @State private var activeSheet: ActiveSheet?
    @State private var showingList = false
    @State private var showingSaveOptions = false
    @State private var showingNamePrompt = false
    @State private var teamName = ""
    @State private var confirmingRebuild = false

    private enum ActiveSheet: Identifiable {
        case player(RatedPlayer)
        case saved
        case share
        case settings

        var id: String {
            switch self {
            case .player(let player): return "player-\(player.id)"
            case .saved: return "saved"
            case .share: return "share"
            case .settings: return "settings"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    summaryStrip
                    if let error = state.editError { errorBanner(error) }
                    toolbar
                    PitchView(squad: squad) { activeSheet = .player($0) }
                    editHint
                    if state.importedTeam != nil { transfersCard }
                    benchStrip
                    notesCard
                    if showingList { fullList }
                    controls
                }
                .padding(20)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .player(let player):
                PlayerDetailView(player: player, squad: squad, editable: true)
                    .environmentObject(state)
            case .saved:
                SavedTeamsView().environmentObject(state)
            case .share:
                ShareOptionsView(squad: squad,
                                 name: state.currentTeamName ?? state.defaultTeamName,
                                 gameweek: state.data?.nextEvent?.name)
            case .settings:
                SettingsView().environmentObject(state)
            }
        }
        .confirmationDialog("Save this team", isPresented: $showingSaveOptions, titleVisibility: .visible) {
            if let name = state.currentTeamName {
                Button("Update “\(name)”") { state.updateCurrentTeam() }
            }
            Button("Save as a new team") {
                teamName = state.defaultTeamName
                showingNamePrompt = true
            }
        }
        .alert("Name this team", isPresented: $showingNamePrompt) {
            TextField("Team name", text: $teamName)
            Button("Save") { state.saveCurrentTeam(name: teamName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It'll reload with live prices and projections whenever you open it.")
        }
        .alert("Throw away your changes?", isPresented: $confirmingRebuild) {
            Button("Rebuild", role: .destructive) { state.build() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rebuilding picks a fresh squad from scratch and loses the transfers and substitutions you made by hand.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.currentTeamName ?? state.importedTeam?.teamName ?? "Your squad")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(squad.formation)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.deepPurple)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.accentGradient))
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(8)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                if let deadline = state.nextDeadline {
                    Text(deadline)
                        .font(.caption)
                        .foregroundStyle(Theme.mint)
                }
                if squad.edited {
                    Text("EDITED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            StatTile(title: "Spent",
                     value: formatPrice(tenths: squad.totalCostTenths),
                     detail: "of \(formatPrice(tenths: squad.budgetTenths))")
            StatTile(title: "In the bank",
                     value: formatPrice(tenths: squad.remainingTenths),
                     detail: "unspent")
            StatTile(title: "Projected",
                     value: String(format: "%.0f", squad.projectedPoints),
                     detail: "pts / GW")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                state.editError = nil
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.35)))
    }

    // MARK: - Save / share / saved teams

    private var toolbar: some View {
        HStack(spacing: 10) {
            pill(title: state.currentTeamID == nil ? "Save" : "Saved", icon: "bookmark.fill") {
                if state.currentTeamID == nil {
                    teamName = state.defaultTeamName
                    showingNamePrompt = true
                } else {
                    showingSaveOptions = true
                }
            }
            pill(title: "Share", icon: "square.and.arrow.up") {
                activeSheet = .share
            }
            pill(title: state.savedTeams.isEmpty ? "My teams" : "My teams (\(state.savedTeams.count))",
                 icon: "folder.fill") {
                activeSheet = .saved
            }
        }
    }

    private func pill(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var editHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(Theme.mint)
            Text("Tap any player to swap them, bench them or hand them the armband.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Suggested transfers

    @ViewBuilder
    private var transfersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Suggested transfers", systemImage: "arrow.left.arrow.right")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Text("\(state.freeTransfersLeft) free")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mint)
            }

            if state.transfersMade > 0 {
                Text("You've made \(state.transfersMade) transfer\(state.transfersMade == 1 ? "" : "s") here.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let plan = state.transferPlan, !plan.isEmpty {
                ForEach(plan.moves) { move in
                    moveRow(move, actionTitle: "Apply")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.moves.count == 1
                         ? String(format: "That's worth about %.1f pts a gameweek.", plan.grossGain)
                         : String(format: "Together they add about %.1f pts a gameweek.", plan.grossGain))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    if plan.hits > 0 {
                        Text("That's \(plan.moves.count) transfers with \(state.freeTransfersLeft) free, so a \(plan.pointsHit)-point hit — worth it only if you keep the gain for more than a week.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if plan.moves.count > 1 {
                    Button("Apply all \(plan.moves.count)") {
                        state.applySuggestedTransfers()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }

                if !plan.alternatives.isEmpty {
                    DisclosureGroup {
                        VStack(spacing: 10) {
                            ForEach(plan.alternatives) { move in
                                moveRow(move, actionTitle: "Swap")
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Other moves worth a look")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.mint)
                    }
                    .tint(Theme.mint)
                }
            } else {
                Text("Nothing worth changing — no transfer I can find improves this squad by enough to bother.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func moveRow(_ move: TransferMove, actionTitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(move.outgoing.element.webName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(move.incoming.element.webName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text("\(move.outgoing.team.shortName) \(formatPrice(tenths: move.outgoing.priceTenths)) → \(move.incoming.team.shortName) \(formatPrice(tenths: move.incoming.priceTenths))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text(String(format: "+%.1f pts/GW", move.gain))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.mint)
            }
            Spacer(minLength: 0)
            Button(actionTitle) {
                state.apply(move)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.deepPurple)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Theme.accentGradient))
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bench

    private var benchStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bench").font(.headline).foregroundStyle(.white)
                Spacer()
                Button {
                    state.autoPickStartingEleven()
                } label: {
                    Label("Auto-pick XI", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mint)
                }
            }
            HStack(spacing: 10) {
                ForEach(Array(squad.bench.enumerated()), id: \.element.id) { index, player in
                    Button {
                        activeSheet = .player(player)
                    } label: {
                        VStack(spacing: 6) {
                            Text(index == 0 && player.position == .goalkeeper ? "GK" : "\(index)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.6))
                            PlayerChip(player: player, badge: nil, compact: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why this team", systemImage: "sparkles")
                .font(.headline).foregroundStyle(.white)

            reasonRow(icon: "star.circle.fill",
                      text: "**\(squad.captain.element.webName)** takes the armband — highest projected return in the XI at \(String(format: "%.1f", squad.captain.projected)) pts. **\(squad.viceCaptain.element.webName)** is vice.")
            reasonRow(icon: "square.grid.3x3.fill",
                      text: "Playing \(squad.formation) with a squad rated \(String(format: "%.1f", squad.startingPoints)) pts per gameweek before the armband.")
            if squad.remainingTenths > 0 {
                reasonRow(icon: "banknote.fill",
                          text: "\(formatPrice(tenths: squad.remainingTenths)) left in the bank.")
            }
            ForEach(squad.notes, id: \.self) { note in
                reasonRow(icon: "checkmark.circle.fill", text: note)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func reasonRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.mint)
            Text(.init(text))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Full list

    private var fullList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Position.allCases) { position in
                let players = squad.squad
                    .filter { $0.position == position }
                    .sorted { $0.projected > $1.projected }
                if !players.isEmpty {
                    Text(position.name.uppercased() + "S")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.mint)
                    ForEach(players) { player in
                        Button { activeSheet = .player(player) } label: {
                            PlayerRow(player: player,
                                      starting: squad.starting.contains(player),
                                      captain: player.id == squad.captain.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Button(showingList ? "Hide the full 15" : "See all 15 with numbers") {
                withAnimation { showingList.toggle() }
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 12) {
                Button {
                    state.editPreferences()
                } label: {
                    Label("Change inputs", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
                Button {
                    if state.settings.confirmBeforeRebuild && squad.edited {
                        confirmingRebuild = true
                    } else {
                        state.build()
                    }
                } label: {
                    Label("Rebuild", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
            }
        }
    }
}

// MARK: - Pitch

struct PitchView: View {
    let squad: OptimizedSquad
    let onSelect: (RatedPlayer) -> Void

    var body: some View {
        VStack(spacing: 18) {
            ForEach(Position.allCases) { position in
                let line = squad.players(position)
                if !line.isEmpty {
                    // Spacing stays tight so a five-man defence still fits.
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(line) { player in
                            Button { onSelect(player) } label: {
                                PlayerChip(
                                    player: player,
                                    badge: badge(for: player),
                                    compact: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                LinearGradient(colors: [Theme.pitchTop, Theme.pitchBottom],
                               startPoint: .top, endPoint: .bottom)
                PitchMarkings()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func badge(for player: RatedPlayer) -> String? {
        if player.id == squad.captain.id { return "C" }
        if player.id == squad.viceCaptain.id { return "V" }
        return nil
    }
}

struct PitchMarkings: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            Path { path in
                // Halfway line and centre circle
                path.move(to: CGPoint(x: 0, y: height / 2))
                path.addLine(to: CGPoint(x: width, y: height / 2))
                path.addEllipse(in: CGRect(x: width / 2 - 46, y: height / 2 - 46, width: 92, height: 92))
                // Penalty boxes
                path.addRect(CGRect(x: width / 2 - 78, y: -20, width: 156, height: 62))
                path.addRect(CGRect(x: width / 2 - 78, y: height - 42, width: 156, height: 62))
            }
            .stroke(.white.opacity(0.16), lineWidth: 1.5)

            // Mown stripes
            ForEach(0..<6) { row in
                Rectangle()
                    .fill(.white.opacity(row.isMultiple(of: 2) ? 0.03 : 0))
                    .frame(height: height / 6)
                    .offset(y: CGFloat(row) * height / 6)
            }
        }
    }
}

// MARK: - Player chip

struct PlayerChip: View {
    let player: RatedPlayer
    let badge: String?
    let compact: Bool

    @Environment(\.showsPlayerPhotos) private var showsPhotos
    @Environment(\.cardDetail) private var detail

    private var size: CGFloat { compact ? 40 : 44 }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(Theme.clubColor(player.team.shortName))
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1.5))
                    if showsPhotos {
                        AsyncImage(url: player.element.photoURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Text(player.team.shortName)
                                    .font(.system(size: compact ? 9 : 10, weight: .black))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                    } else {
                        Text(player.team.shortName)
                            .font(.system(size: compact ? 10 : 11, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)

                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.deepPurple)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Theme.mint))
                        .offset(x: 4, y: -3)
                }

                if case .available = player.availability {} else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                        .offset(x: 4, y: size - 12)
                }
            }

            Text(player.element.webName)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // The club label matters: FPL reuses last season's photos, so a
            // summer signing still appears in their old kit.
            if detail.showsPrice {
                Text("\(player.team.shortName) · \(formatPrice(tenths: player.priceTenths))")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if detail.showsProjection {
                Text(String(format: "%.1f pts", player.projected))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.mint)
            }
        }
        .frame(width: compact ? 66 : 62)
    }
}

// MARK: - Rows and tiles

struct PlayerRow: View {
    let player: RatedPlayer
    var starting: Bool = true
    var captain: Bool = false

    @Environment(\.showsOwnership) private var showsOwnership

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.clubColor(player.team.shortName))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.element.webName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if captain {
                        Text("C")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Theme.deepPurple)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(Theme.mint))
                    }
                    if !starting {
                        Text("BENCH")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.12)))
                    }
                }
                Text(showsOwnership
                     ? String(format: "%@ · %@ · %.1f%% owned", player.team.shortName, player.position.short, player.element.ownership)
                     : "\(player.team.shortName) · \(player.position.short)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPrice(tenths: player.priceTenths))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(String(format: "%.1f pts/GW", player.projected))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.mint)
            }
        }
        .padding(.vertical, 6)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}
