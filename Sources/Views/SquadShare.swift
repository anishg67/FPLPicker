import SwiftUI

/// Text and image renditions of a squad, for the system share sheet.
enum SquadShare {

    static func text(_ squad: OptimizedSquad, name: String, gameweek: String?) -> String {
        var lines: [String] = []
        lines.append("⚽️ \(name)")
        if let gameweek { lines.append(gameweek) }
        lines.append("\(squad.formation) · \(formatPrice(tenths: squad.totalCostTenths)) of \(formatPrice(tenths: squad.budgetTenths)) · \(String(format: "%.0f", squad.projectedPoints)) projected pts/GW")
        lines.append("")

        for position in Position.allCases {
            let line = squad.starting.filter { $0.position == position }
            guard !line.isEmpty else { continue }
            let names = line.map { player -> String in
                var label = "\(player.element.webName) (\(player.team.shortName) \(formatPrice(tenths: player.priceTenths)))"
                if player.id == squad.captain.id { label += " (C)" }
                if player.id == squad.viceCaptain.id { label += " (V)" }
                return label
            }
            lines.append("\(position.short): \(names.joined(separator: ", "))")
        }

        let bench = squad.bench.map { "\($0.element.webName) (\($0.team.shortName) \(formatPrice(tenths: $0.priceTenths)))" }
        lines.append("Bench: \(bench.joined(separator: ", "))")
        lines.append("")
        lines.append("Built with Squad Picker Pro")
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func image(_ squad: OptimizedSquad, name: String, gameweek: String?) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(squad: squad, name: name, gameweek: gameweek))
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 380, height: nil)
        return renderer.uiImage
    }
}

/// The shareable card. Deliberately avoids AsyncImage — remote photos would not
/// have loaded by the time ImageRenderer snapshots the view.
struct ShareCardView: View {
    let squad: OptimizedSquad
    let name: String
    let gameweek: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                if let gameweek {
                    Text(gameweek)
                        .font(.caption)
                        .foregroundStyle(Theme.mint)
                }
            }

            HStack(spacing: 8) {
                shareStat("SPENT", formatPrice(tenths: squad.totalCostTenths))
                shareStat("SHAPE", squad.formation)
                shareStat("PROJECTED", String(format: "%.0f pts", squad.projectedPoints))
            }

            VStack(spacing: 12) {
                ForEach(Position.allCases) { position in
                    let line = squad.starting.filter { $0.position == position }
                    if !line.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(line) { player in
                                sharePlayer(player)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Theme.pitchTop, Theme.pitchBottom],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("BENCH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(squad.bench.map { "\($0.element.webName) (\($0.team.shortName))" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Text("Built with Squad Picker Pro")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(18)
        .frame(width: 380)
        .background(Theme.background)
    }

    private func shareStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
    }

    private func sharePlayer(_ player: RatedPlayer) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Theme.clubColor(player.team.shortName))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(player.team.shortName)
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                    )
                if player.id == squad.captain.id {
                    Text("C")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Theme.deepPurple)
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(Theme.mint))
                        .offset(x: 3, y: -3)
                }
            }
            Text(player.element.webName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(formatPrice(tenths: player.priceTenths))
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 62)
    }
}
