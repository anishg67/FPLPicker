import SwiftUI

struct RootView: View {
    @StateObject private var state = AppState()

    var body: some View {
        Group {
            switch state.phase {
            case .loading:
                StatusView(title: "Pulling live player data",
                           subtitle: "Prices, form and the fixture list, straight from the game.",
                           spinning: true)
            case .failed(let message):
                StatusView(title: "Couldn't reach the data feed",
                           subtitle: message,
                           spinning: false) {
                    Button("Try again") { state.retry() }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 40)
                }
            case .survey:
                SurveyView()
            case .importTeam:
                ImportTeamView()
            case .preferences:
                PreferencesView()
            case .building:
                StatusView(title: "Building your squad",
                           subtitle: "Searching legal 15-man squads under your budget and club limits.",
                           spinning: true)
            case .result:
                if let squad = state.squad {
                    SquadView(squad: squad)
                } else {
                    PreferencesView()
                }
            }
        }
        .environmentObject(state)
        .environment(\.accentTheme, state.settings.accent)
        .environment(\.showsPlayerPhotos, state.settings.showPlayerPhotos)
        .environment(\.cardDetail, state.settings.cardDetail)
        .environment(\.showsOwnership, state.settings.showOwnership)
        .preferredColorScheme(.dark)
        .task { await state.start() }
    }
}

struct StatusView<Action: View>: View {
    let title: String
    let subtitle: String
    let spinning: Bool
    @ViewBuilder var action: () -> Action

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                if spinning {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.mint)
                } else {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.mint)
                }
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                action()
            }
            .padding(32)
        }
    }
}

extension StatusView where Action == EmptyView {
    init(title: String, subtitle: String, spinning: Bool) {
        self.init(title: title, subtitle: subtitle, spinning: spinning) { EmptyView() }
    }
}
