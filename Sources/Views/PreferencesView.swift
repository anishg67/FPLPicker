import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var state: AppState
    @State private var showingPlayerPicker: PlayerPickerTarget?
    @State private var showingModeSheet = false
    @State private var showingSavedTeams = false
    @State private var showingGlossary = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let error = state.buildError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.35)))
                    }

                    if state.prefs.mode == .auto {
                        autoSection
                    } else {
                        budgetCard
                        teamCard
                    }
                    if state.prefs.mode == .expert {
                        tuningCard
                        shortlistCard
                    }

                    if let validation {
                        Label(validation, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.yellow)
                    }

                    Button(state.prefs.mode == .auto ? "Build my team" : "Build my squad") {
                        state.build()
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: validation == nil))
                    .disabled(validation != nil)
                    .padding(.top, 4)

                    if state.squad != nil {
                        Button("Back to my squad") { state.phase = .result }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
        }
        .sheet(item: $showingPlayerPicker) { target in
            PlayerPickerView(target: target)
                .environmentObject(state)
        }
        .sheet(isPresented: $showingSavedTeams) {
            SavedTeamsView().environmentObject(state)
        }
        .sheet(isPresented: $showingGlossary) { GlossaryView() }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(state) }
        .confirmationDialog("How much control do you want?", isPresented: $showingModeSheet, titleVisibility: .visible) {
            ForEach(SkillMode.allCases) { mode in
                Button(mode.title) {
                    state.prefs.mode = mode
                    state.refreshRatings()
                }
            }
            Button("Retake the survey") { state.retakeSurvey() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Squad Picker")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    if let deadline = state.nextDeadline {
                        Text(deadline)
                            .font(.caption)
                            .foregroundStyle(Theme.mint)
                    }
                }
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(8)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Button {
                    showingModeSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: state.prefs.mode.icon)
                        Text(state.prefs.mode.title)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
            }
            Text(state.prefs.mode.blurb)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    state.startImport()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("I already have a team")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    showingGlossary = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                        Text("Jargon")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            if !state.savedTeams.isEmpty {
                Button {
                    showingSavedTeams = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                        Text("Open a saved team (\(state.savedTeams.count))")
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Auto

    private var autoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What I'll do")
                .font(.headline).foregroundStyle(.white)
            ForEach(autoBullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.mint)
                    Text(bullet)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var autoBullets: [String] {
        [
            "Spend the standard £100.0m budget across 15 players.",
            "Respect every squad rule: 2 keepers, 5 defenders, 5 midfielders, 3 forwards, max 3 from any one club.",
            "Weigh form, season-long returns, underlying stats and the next 5 gameweeks of fixtures.",
            "Pick your best starting XI, formation, captain and bench order."
        ]
    }

    // MARK: - Budget

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Budget").font(.headline).foregroundStyle(.white)
                Spacer()
                Text(formatPrice(tenths: state.prefs.budgetTenths))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.mint)
            }
            Slider(
                value: Binding(
                    get: { Double(state.prefs.budgetTenths) },
                    set: { state.prefs.budgetTenths = Int($0.rounded()) }
                ),
                in: 800...1200, step: 5
            )
            .tint(Theme.mint)
            Text("New teams start with £100.0m. Set it lower for a challenge, or higher if your squad value has grown.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .card()
    }

    // MARK: - Clubs

    private var teamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clubs").font(.headline).foregroundStyle(.white)
                Spacer()
                if !state.prefs.preferredTeams.isEmpty {
                    Button("Clear") { state.prefs.preferredTeams = [] }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mint)
                }
            }

            Picker("", selection: $state.prefs.teamMode) {
                ForEach(TeamPreferenceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(state.prefs.teamMode.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))

            FlowLayout(spacing: 8) {
                ForEach(sortedTeams) { team in
                    let selected = state.prefs.preferredTeams.contains(team.id)
                    Button {
                        if selected { state.prefs.preferredTeams.remove(team.id) }
                        else { state.prefs.preferredTeams.insert(team.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.clubColor(team.shortName))
                                .frame(width: 10, height: 10)
                            Text(team.shortName)
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(selected ? Theme.deepPurple : .white)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(
                            Capsule().fill(selected ? AnyShapeStyle(Theme.accentGradient)
                                                    : AnyShapeStyle(Color.white.opacity(0.12)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private var sortedTeams: [FPLTeam] {
        (state.data?.teams ?? []).sorted { $0.shortName < $1.shortName }
    }

    // MARK: - Expert tuning

    private var tuningCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Strategy").font(.headline).foregroundStyle(.white)

            labelledSlider(
                title: "Risk appetite",
                value: $state.prefs.riskAppetite,
                range: -1...1,
                readout: riskLabel,
                help: "Left leans on heavily-owned template picks. Right hunts differentials the crowd doesn't own."
            )

            labelledSlider(
                title: "Form vs season",
                value: $state.prefs.formWeight,
                range: 0...0.8,
                readout: "\(Int(state.prefs.formWeight * 100))% form",
                help: "How much recent form outweighs season-long output."
            )

            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $state.prefs.fixtureHorizon, in: 1...10) {
                    HStack {
                        Text("Fixture horizon").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(state.prefs.fixtureHorizon) GW")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.mint)
                    }
                }
                .tint(Theme.mint)
                Text("How many upcoming gameweeks of fixture difficulty to weigh.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: $state.prefs.maxPerClub, in: 1...3) {
                    HStack {
                        Text("Max per club").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(state.prefs.maxPerClub)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.mint)
                    }
                }
                .tint(Theme.mint)
                Text("The game's own limit is 3. Lower it to spread risk across more clubs.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }

            Toggle(isOn: $state.prefs.avoidInjuryRisk) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Skip injured and suspended players")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Also punishes rotation risk more heavily.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
            .tint(Theme.mint)
        }
        .card()
    }

    private var riskLabel: String {
        switch state.prefs.riskAppetite {
        case ..<(-0.5): return "Full template"
        case ..<(-0.15): return "Safe"
        case ..<0.15: return "Balanced"
        case ..<0.5: return "Punchy"
        default: return "Differential hunter"
        }
    }

    private func labelledSlider(title: String,
                                value: Binding<Double>,
                                range: ClosedRange<Double>,
                                readout: String,
                                help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Text(readout).font(.caption.weight(.semibold)).foregroundStyle(Theme.mint)
            }
            Slider(value: value, in: range).tint(Theme.mint)
            Text(help).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Must-have / blocklist

    private var shortlistCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            shortlistSection(
                title: "Must have",
                systemImage: "pin.fill",
                ids: state.prefs.mustInclude,
                empty: "Lock in players you refuse to be without.",
                add: { showingPlayerPicker = .mustInclude },
                remove: { state.prefs.mustInclude.remove($0) }
            )
            Divider().overlay(.white.opacity(0.15))
            shortlistSection(
                title: "Never pick",
                systemImage: "nosign",
                ids: state.prefs.exclude,
                empty: "Block players you don't want anywhere near your team.",
                add: { showingPlayerPicker = .exclude },
                remove: { state.prefs.exclude.remove($0) }
            )
        }
        .card()
    }

    private func shortlistSection(title: String,
                                  systemImage: String,
                                  ids: Set<Int>,
                                  empty: String,
                                  add: @escaping () -> Void,
                                  remove: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Button {
                    add()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.mint)
                }
            }
            if ids.isEmpty {
                Text(empty).font(.caption).foregroundStyle(.white.opacity(0.55))
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(ids), id: \.self) { id in
                        if let player = state.player(id: id) {
                            Button {
                                remove(id)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(player.element.webName)
                                        .font(.caption.weight(.semibold))
                                    Image(systemName: "xmark")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.clubColor(player.team.shortName).opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Validation

    private var validation: String? {
        let prefs = state.prefs
        guard prefs.mode != .auto else { return nil }
        if prefs.teamMode == .only && !prefs.preferredTeams.isEmpty {
            let needed = Int(ceil(15.0 / Double(max(1, prefs.maxPerClub))))
            if prefs.preferredTeams.count < needed {
                return "Pick at least \(needed) clubs — with a cap of \(prefs.maxPerClub) per club you can't fill 15 places otherwise."
            }
        }
        if prefs.teamMode == .only && prefs.preferredTeams.isEmpty {
            return "Select the clubs you want players from, or switch to “Favour them”."
        }
        if !prefs.mustInclude.isEmpty {
            let cost = prefs.mustInclude.compactMap { state.player(id: $0)?.priceTenths }.reduce(0, +)
            if cost > prefs.budgetTenths {
                return "Your must-have players alone cost \(formatPrice(tenths: cost))."
            }
        }
        return nil
    }
}

enum PlayerPickerTarget: String, Identifiable {
    case mustInclude, exclude
    var id: String { rawValue }
    var title: String { self == .mustInclude ? "Must have" : "Never pick" }
}

/// Wrapping chip layout — used for club chips and shortlist pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
