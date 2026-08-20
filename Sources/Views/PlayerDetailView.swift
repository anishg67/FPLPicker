import SwiftUI

struct PlayerDetailView: View {
    let player: RatedPlayer
    let squad: OptimizedSquad?
    /// False when opened from a shortlist picker, where edits make no sense.
    var editable: Bool = false

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        if !player.element.news.isEmpty {
                            Label(player.element.news, systemImage: "cross.case.fill")
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.3)))
                        }
                        if editable, squad != nil { actions }
                        if !player.reasons.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Why I rate them").font(.headline).foregroundStyle(.white)
                                ForEach(player.reasons, id: \.self) { reason in
                                    Label(reason, systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                        statsGrid
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents(editable ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Editing actions

    private var isStarting: Bool { state.isStarting(player) }
    private var isCaptain: Bool { squad?.captain.id == player.id }
    private var isVice: Bool { squad?.viceCaptain.id == player.id }

    private var actions: some View {
        VStack(spacing: 10) {
            if isStarting {
                HStack(spacing: 10) {
                    actionButton(title: isCaptain ? "Captain" : "Make captain",
                                 icon: "star.fill",
                                 highlighted: isCaptain,
                                 disabled: isCaptain) {
                        state.makeCaptain(player)
                        dismiss()
                    }
                    actionButton(title: isVice ? "Vice-captain" : "Make vice",
                                 icon: "star.leadinghalf.filled",
                                 highlighted: isVice,
                                 disabled: isVice) {
                        state.makeViceCaptain(player)
                        dismiss()
                    }
                }
            }

            NavigationLink {
                SubstitutePickerView(player: player, onFinished: { dismiss() })
                    .environmentObject(state)
            } label: {
                actionRow(title: isStarting ? "Bench \(player.element.webName)" : "Bring on for…",
                          detail: isStarting ? "Swap with someone on your bench" : "Swap with a player in your XI",
                          icon: "arrow.up.arrow.down")
            }

            NavigationLink {
                TransferMarketView(outgoing: player, onFinished: { dismiss() })
                    .environmentObject(state)
            } label: {
                actionRow(title: "Replace with another \(player.position.short)",
                          detail: "Anyone you can afford under the club limit",
                          icon: "arrow.left.arrow.right")
            }
        }
    }

    private func actionButton(title: String,
                              icon: String,
                              highlighted: Bool,
                              disabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? Theme.deepPurple : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(highlighted ? AnyShapeStyle(Theme.accentGradient)
                                               : AnyShapeStyle(Color.white.opacity(0.14)))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func actionRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.mint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    // MARK: - Header and stats

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.clubColor(player.team.shortName))
                AsyncImage(url: player.element.photoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Text(player.team.shortName)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
            }
            .frame(width: 72, height: 72)
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(player.element.webName)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("\(player.element.fullName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    tag(player.team.shortName)
                    tag(player.position.short)
                    tag(formatPrice(tenths: player.priceTenths))
                    if isCaptain { tag("CAPTAIN") }
                    else if squad != nil && editable && !isStarting { tag("BENCH") }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.15)))
    }

    private var statsGrid: some View {
        let element = player.element
        let stats: [(String, String)] = [
            ("Projected", String(format: "%.1f pts/GW", player.projected)),
            ("Value", String(format: "%.2f pts per £m", player.valueRatio)),
            ("Total points", "\(element.totalPoints)"),
            ("Points per game", element.pointsPerGame.text()),
            ("Form", element.form.text()),
            ("Minutes", "\(element.minutes)"),
            ("Ownership", String(format: "%.1f%%", element.ownership)),
            ("Fixture difficulty", String(format: "%.1f avg", player.fixtureScore)),
            ("Goals", "\(element.goalsScored)"),
            ("Assists", "\(element.assists)"),
            (element.position == .goalkeeper ? "Saves" : "Clean sheets",
             element.position == .goalkeeper ? "\(element.saves)" : "\(element.cleanSheets)"),
            ("xGI / 90", element.expectedGoalInvolvementsPer90.text("%.2f"))
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(stats, id: \.0) { stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.0.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(stat.1)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
            }
        }
    }
}

// MARK: - Transfers

/// Swap one player for another of the same position, showing exactly why a
/// candidate can't be picked rather than hiding them.
struct TransferMarketView: View {
    let outgoing: RatedPlayer
    let onFinished: () -> Void

    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var affordableOnly = true

    private var options: [TransferOption] {
        let all = state.transferOptions(for: outgoing, query: query)
        return affordableOnly ? all.filter(\.selectable) : all
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                List {
                    ForEach(options) { option in
                        Button {
                            state.replace(outgoing, with: option.player)
                            onFinished()
                        } label: {
                            row(option)
                        }
                        .disabled(!option.selectable)
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                    if options.isEmpty {
                        Text("Nobody matches. Try turning off “affordable only”.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $query, prompt: "Search \(outgoing.position.name.lowercased())s")
        .navigationTitle("Replace \(outgoing.element.webName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.deepPurple, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You can spend up to \(formatPrice(tenths: budgetForSlot)) on this slot.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
            Toggle("Only show players I can pick", isOn: $affordableOnly)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .tint(Theme.mint)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var budgetForSlot: Int {
        guard let squad = state.squad else { return outgoing.priceTenths }
        return squad.budgetTenths - squad.totalCostTenths + outgoing.priceTenths
    }

    private func row(_ option: TransferOption) -> some View {
        HStack {
            PlayerRow(player: option.player)
            VStack(alignment: .trailing, spacing: 3) {
                if let reason = option.blockReason {
                    Text(reason)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(option.deltaLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(option.priceDelta > 0 ? .orange : Theme.mint)
                }
            }
        }
        .opacity(option.selectable ? 1 : 0.45)
    }
}

// MARK: - Substitutions

struct SubstitutePickerView: View {
    let player: RatedPlayer
    let onFinished: () -> Void

    @EnvironmentObject var state: AppState

    private var partners: [RatedPlayer] { state.substitutionPartners(for: player) }
    private var isStarting: Bool { state.isStarting(player) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(partners) { partner in
                        Button {
                            if isStarting {
                                state.substitute(starter: player, with: partner)
                            } else {
                                state.substitute(starter: partner, with: player)
                            }
                            onFinished()
                        } label: {
                            PlayerRow(player: partner, starting: !isStarting)
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                    if partners.isEmpty {
                        Text("No legal swap here — it would break the formation rules.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(isStarting ? "Bring on instead" : "Take off for \(player.element.webName)")
                        .foregroundStyle(Theme.mint)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Substitute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.deepPurple, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Shortlist picker (must-have / blocklist)

/// Search-and-tap list used for the must-have and blocklist shortlists.
struct PlayerPickerView: View {
    let target: PlayerPickerTarget
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var position: Position?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(title: "All", active: position == nil) { position = nil }
                            ForEach(Position.allCases) { pos in
                                filterChip(title: pos.short, active: position == pos) { position = pos }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    List {
                        ForEach(state.searchPlayers(query, position: position).prefix(120)) { player in
                            Button {
                                toggle(player)
                            } label: {
                                HStack {
                                    PlayerRow(player: player)
                                    if isSelected(player) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.mint)
                                    }
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .searchable(text: $query, prompt: "Search players or clubs")
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.mint)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func filterChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(active ? Theme.deepPurple : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(active ? AnyShapeStyle(Theme.accentGradient)
                                                  : AnyShapeStyle(Color.white.opacity(0.12))))
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ player: RatedPlayer) -> Bool {
        target == .mustInclude
            ? state.prefs.mustInclude.contains(player.id)
            : state.prefs.exclude.contains(player.id)
    }

    private func toggle(_ player: RatedPlayer) {
        switch target {
        case .mustInclude:
            if state.prefs.mustInclude.contains(player.id) {
                state.prefs.mustInclude.remove(player.id)
            } else {
                state.prefs.mustInclude.insert(player.id)
                state.prefs.exclude.remove(player.id)
            }
        case .exclude:
            if state.prefs.exclude.contains(player.id) {
                state.prefs.exclude.remove(player.id)
            } else {
                state.prefs.exclude.insert(player.id)
                state.prefs.mustInclude.remove(player.id)
            }
        }
    }
}
