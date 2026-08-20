import SwiftUI

/// Searchable jargon buster, reachable from the survey and the inputs screen.
struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Every bit of jargon this app uses, in plain English. Nothing here is required reading — the app works fine if you skip it.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.bottom, 4)

                        ForEach(Glossary.search(query)) { term in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(term.term)
                                        .font(.headline)
                                        .foregroundStyle(Theme.mint)
                                    if let short = term.short {
                                        Text(short)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                                Text(term.definition)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let example = term.example {
                                    Text(example)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.55))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }

                        if Glossary.search(query).isEmpty {
                            Text("Nothing matches “\(query)”.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(20)
                }
            }
            .searchable(text: $query, prompt: "Search the jargon")
            .navigationTitle("Jargon buster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.deepPurple, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.mint)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
