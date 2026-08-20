import SwiftUI

struct SavedTeamsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedTeam?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if state.savedTeams.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.mint)
                        Text("No saved teams yet")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Build a squad and tap Save to keep it here. Saved teams reload with today's prices and projections.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    List {
                        ForEach(state.savedTeams) { team in
                            Button {
                                state.load(team)
                                dismiss()
                            } label: {
                                row(team)
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    state.delete(team)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    newName = team.name
                                    renaming = team
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Saved teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.mint)
                }
            }
            .alert("Rename team", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Team name", text: $newName)
                Button("Save") {
                    if let team = renaming { state.rename(team, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ team: SavedTeam) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(team.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if state.currentTeamID == team.id {
                        Text("ON SCREEN")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.deepPurple)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.mint))
                    }
                }
                Text(team.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                if let gameweek = team.gameweek {
                    Text(gameweek)
                        .font(.caption2)
                        .foregroundStyle(Theme.mint.opacity(0.8))
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 6)
    }
}

/// Share sheet options: the squad as a picture, or as plain text.
struct ShareOptionsView: View {
    let squad: OptimizedSquad
    let name: String
    let gameweek: String?

    @Environment(\.dismiss) private var dismiss
    @State private var rendered: UIImage?

    private var text: String { SquadShare.text(squad, name: name, gameweek: gameweek) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        if let rendered {
                            Image(uiImage: rendered)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                                .padding(.horizontal, 4)

                            ShareLink(
                                item: Image(uiImage: rendered),
                                preview: SharePreview(name, image: Image(uiImage: rendered))
                            ) {
                                Label("Share as image", systemImage: "photo")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        } else {
                            ProgressView().tint(Theme.mint).padding(30)
                        }

                        ShareLink(item: text) {
                            Label("Share as text", systemImage: "text.alignleft")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(.white.opacity(0.14)))
                        }

                        Text(text)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Share squad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.mint)
                }
            }
            .task {
                rendered = SquadShare.image(squad, name: name, gameweek: gameweek)
            }
        }
        .preferredColorScheme(.dark)
    }
}
