import Foundation

/// Plain-English definitions for the jargon the app (and the FPL community) uses.
struct GlossaryTerm: Identifiable, Hashable {
    let term: String
    let short: String?         // expansion, e.g. "expected goals"
    let definition: String
    let example: String?

    var id: String { term }
}

enum Glossary {
    static let terms: [GlossaryTerm] = [
        GlossaryTerm(
            term: "xG",
            short: "expected goals",
            definition: "How many goals a player would be expected to score from the chances they got. A tap-in is worth close to 1.0 xG, a speculative shot from 30 yards maybe 0.02.",
            example: "A striker with 0.6 xG in a match had chances a typical player scores from about 60% of the time — whether or not they actually scored."
        ),
        GlossaryTerm(
            term: "xA",
            short: "expected assists",
            definition: "The same idea for passes: how likely the chances a player created were to be scored by a teammate.",
            example: "A cross that lands on a striker's head six yards out is high xA even if it's headed wide."
        ),
        GlossaryTerm(
            term: "xGI",
            short: "expected goal involvements",
            definition: "xG and xA added together — a single number for how much attacking threat a player produces.",
            example: nil
        ),
        GlossaryTerm(
            term: "Per 90",
            short: "per 90 minutes",
            definition: "A stat adjusted to a full match, so substitutes and injured players can be compared fairly with players who start every week.",
            example: "2 goals in 180 minutes is 1.0 goals per 90."
        ),
        GlossaryTerm(
            term: "FDR",
            short: "fixture difficulty rating",
            definition: "The game's 1-to-5 score for how hard each upcoming match is. 1 and 2 are kind fixtures, 4 and 5 are tough ones. This app averages it over the next few gameweeks.",
            example: "A defence averaging 2.1 FDR has an easy run and is more likely to keep clean sheets."
        ),
        GlossaryTerm(
            term: "Clean sheet",
            short: nil,
            definition: "Conceding no goals. Goalkeepers and defenders get 4 points for one, midfielders get 1, and it's worth nothing if the player was on for under 60 minutes.",
            example: nil
        ),
        GlossaryTerm(
            term: "Bonus and BPS",
            short: "bonus points system",
            definition: "After every match the three best performers get 3, 2 and 1 extra points, decided by a behind-the-scenes score called BPS that rewards goals, assists, tackles, saves and passes.",
            example: nil
        ),
        GlossaryTerm(
            term: "Ownership",
            short: "selected by percent",
            definition: "The share of all managers who own a player. High ownership means everyone has them, so they protect your rank rather than improve it.",
            example: "A 70%-owned striker who blanks costs you nothing relative to the field. Missing him when he hauls is what hurts."
        ),
        GlossaryTerm(
            term: "EO",
            short: "effective ownership",
            definition: "Ownership adjusted for captaincy — a player owned by 50% and captained by 40% has an effective ownership of about 90%, because captains score double.",
            example: nil
        ),
        GlossaryTerm(
            term: "Differential",
            short: nil,
            definition: "A player almost nobody owns. If they return, you gain ground on everyone who doesn't have them. If they don't, you lose very little.",
            example: "Under about 5% ownership is usually considered a differential."
        ),
        GlossaryTerm(
            term: "Template",
            short: nil,
            definition: "The squad most top managers converge on. Owning it keeps you moving with the crowd instead of against it — safe, but it won't win you a mini-league on its own.",
            example: nil
        ),
        GlossaryTerm(
            term: "Free transfer",
            short: nil,
            definition: "A swap you can make without penalty. You get one each gameweek and can save them up — this app assumes the current rules, where up to five can be banked.",
            example: nil
        ),
        GlossaryTerm(
            term: "Hit",
            short: "points hit",
            definition: "Every transfer beyond your free ones costs 4 points. Only worth taking if you expect the new player to beat the old one by more than that.",
            example: "A −4 hit that gains you 6 points is a net 2-point win."
        ),
        GlossaryTerm(
            term: "Bank",
            short: "in the bank",
            definition: "Money you haven't spent. It sits unused but gives you room to upgrade later.",
            example: nil
        ),
        GlossaryTerm(
            term: "Price change",
            short: nil,
            definition: "Player prices drift up or down by £0.1m based on how many managers are buying or selling them. Buying early is how squad value grows.",
            example: nil
        ),
        GlossaryTerm(
            term: "Nailed",
            short: nil,
            definition: "A player certain to start every week. The opposite is rotation risk — someone the manager rests or benches unpredictably.",
            example: nil
        ),
        GlossaryTerm(
            term: "Double and blank gameweeks",
            short: nil,
            definition: "Fixture rescheduling means some clubs play twice in a gameweek (a double) and some don't play at all (a blank). Doubles are worth loading up on.",
            example: nil
        )
    ]

    static func search(_ query: String) -> [GlossaryTerm] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return terms }
        return terms.filter {
            $0.term.lowercased().contains(trimmed)
                || ($0.short ?? "").lowercased().contains(trimmed)
                || $0.definition.lowercased().contains(trimmed)
        }
    }
}
