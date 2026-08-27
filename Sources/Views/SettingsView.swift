import SwiftUI

/// App-wide customisation: how the app looks, what the cards show, what the
/// defaults are, and the switches for wiping stored data.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showingGlossary = false
    @State private var confirmingDeleteTeams = false
    @State private var confirmingReset = false
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        appearanceCard
                        cardsCard
                        defaultsCard
                        dataCard
                        aboutCard
                        dangerCard
                        byline
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.mint)
                }
            }
            .sheet(isPresented: $showingGlossary) { GlossaryView() }
            .alert("Delete every saved team?", isPresented: $confirmingDeleteTeams) {
                Button("Delete", role: .destructive) { state.deleteAllSavedTeams() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all \(state.savedTeams.count) saved teams from this device. It can't be undone.")
            }
            .alert("Reset the app?", isPresented: $confirmingReset) {
                Button("Reset everything", role: .destructive) {
                    state.resetEverything()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clears your survey answers, inputs, saved teams and the squad you entered, then starts the survey again.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Appearance", icon: "paintbrush.fill")

            Text("Accent colour")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                ForEach(AccentTheme.allCases) { accent in
                    Button {
                        state.settings.accent = accent
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(LinearGradient(colors: [accent.primary, accent.secondary],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(.white,
                                                    lineWidth: state.settings.accent == accent ? 3 : 0)
                                )
                            Text(accent.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(state.settings.accent == accent
                                                 ? .white : .white.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle(isOn: $state.settings.showPlayerPhotos) {
                settingLabel("Player photos",
                             "Off shows club-coloured badges instead. Photos are last season's, so summer signings appear in old kits.")
            }
            .tint(Theme.mint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Cards

    private var cardsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Player cards", icon: "rectangle.stack.fill")

            Picker("", selection: $state.settings.cardDetail) {
                ForEach(CardDetail.allCases) { detail in
                    Text(detail.name).tag(detail)
                }
            }
            .pickerStyle(.segmented)

            Text(state.settings.cardDetail.detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))

            Toggle(isOn: $state.settings.showOwnership) {
                settingLabel("Show ownership",
                             "Adds the percentage of managers who own each player to the player lists.")
            }
            .tint(Theme.mint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Defaults

    private var defaultsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Defaults", icon: "slider.horizontal.3")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Budget for new squads")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(formatPrice(tenths: state.settings.defaultBudgetTenths))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.mint)
                }
                Slider(
                    value: Binding(
                        get: { Double(state.settings.defaultBudgetTenths) },
                        set: { state.settings.defaultBudgetTenths = Int($0.rounded()) }
                    ),
                    in: 800...1200, step: 5
                )
                .tint(Theme.mint)
                Text("Used when the app picks a squad without being told a budget. Most fantasy teams start at £100.0m.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Toggle(isOn: $state.settings.confirmBeforeRebuild) {
                settingLabel("Confirm before rebuilding",
                             "Asks first when a rebuild would throw away transfers or substitutions you made by hand.")
            }
            .tint(Theme.mint)

            Button {
                state.retakeSurvey()
                dismiss()
            } label: {
                settingRow("Retake the survey",
                           detail: "Currently: \(state.survey?.label ?? "not taken") · \(state.prefs.mode.title)",
                           icon: "list.bullet.clipboard")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Data", icon: "arrow.triangle.2.circlepath")

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live player data")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(state.dataAgeDescription ?? "Not loaded")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button {
                    Task {
                        isRefreshing = true
                        await state.refreshData()
                        isRefreshing = false
                    }
                } label: {
                    if isRefreshing {
                        ProgressView().tint(Theme.deepPurple).frame(width: 70)
                    } else {
                        Text("Refresh").font(.caption.weight(.bold)).frame(width: 70)
                    }
                }
                .padding(.vertical, 11)
                .background(Capsule().fill(Theme.accentGradient))
                .foregroundStyle(Theme.deepPurple)
                .buttonStyle(.plain)
            }

            Text("Prices, form, injuries and fixture difficulty come straight from the game's public data feed. Refreshing re-prices the squad on screen without changing your picks.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            if state.importedTeam != nil {
                Button {
                    state.forgetImportedTeam()
                } label: {
                    settingRow("Forget my entered team",
                               detail: "Stop working from the squad you typed in or imported",
                               icon: "person.crop.circle.badge.xmark")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("About", icon: "info.circle.fill")

            Button {
                showingGlossary = true
            } label: {
                settingRow("Jargon buster",
                           detail: "xG, xA, FDR, EO and the rest, in plain English",
                           icon: "book.fill")
            }
            .buttonStyle(.plain)

            HStack {
                Text("Version").font(.caption).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(appVersion).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            Text("Unofficial and independent. Not affiliated with any football competition, club or fantasy game provider.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Destructive

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Stored data", icon: "trash.fill")

            Button {
                confirmingDeleteTeams = true
            } label: {
                settingRow("Delete saved teams",
                           detail: state.savedTeams.isEmpty
                               ? "Nothing saved yet"
                               : "\(state.savedTeams.count) saved on this device",
                           icon: "folder.badge.minus",
                           destructive: true)
            }
            .buttonStyle(.plain)
            .disabled(state.savedTeams.isEmpty)

            Button {
                confirmingReset = true
            } label: {
                settingRow("Reset everything",
                           detail: "Clear all answers, inputs and squads, then start over",
                           icon: "arrow.counterclockwise",
                           destructive: true)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Byline

    private var byline: some View {
        VStack(spacing: 4) {
            Text("by Anish Gupta")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.mint)
            Text("Squad Picker")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Building blocks

    private func sectionTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private func settingLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingRow(_ title: String,
                            detail: String,
                            icon: String,
                            destructive: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(destructive ? .red : Theme.mint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(destructive ? .red : .white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 4)
    }
}
