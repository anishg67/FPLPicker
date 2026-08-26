import SwiftUI

struct SurveyQuestion: Identifiable {
    enum Kind {
        case teamStatus     // routes to the import flow, doesn't score
        case knowledge      // feeds the football-knowledge score
        case control        // how much the user wants to decide
    }

    let id: Int
    let kind: Kind
    let prompt: String
    let subtitle: String
    var showsGlossary: Bool = false
    let options: [Option]

    struct Option: Identifiable {
        let id = UUID()
        let text: String
        let detail: String?
        let score: Int          // 0...3, how much football knowledge it implies
    }
}

enum SurveyContent {
    /// Team status first, then four knowledge questions, then how much control
    /// the user wants.
    static let questions: [SurveyQuestion] = [
        SurveyQuestion(
            id: 0,
            kind: .teamStatus,
            prompt: "Do you already have a fantasy football team?",
            subtitle: "If you do, I'll work from your real squad — your players, your bank, your free transfers — and suggest changes. If not, I'll build you one from nothing.",
            options: [
                .init(text: "No, I'm starting from scratch",
                      detail: "Build me a whole squad", score: 0),
                .init(text: "Yes — import it with my team ID",
                      detail: "I'll pull your squad, bank and squad value straight from the game", score: 0),
                .init(text: "Yes — I'll enter my 15 by hand",
                      detail: "Pick your players, then tell me your bank and free transfers", score: 0)
            ]
        ),
        SurveyQuestion(
            id: 1,
            kind: .knowledge,
            prompt: "How much top-flight football do you actually watch?",
            subtitle: "No wrong answer — this just sets how much I explain.",
            options: [
                .init(text: "Basically none", detail: "I know the sport exists", score: 0),
                .init(text: "The odd big game", detail: "Derbies, finals, highlights", score: 1),
                .init(text: "Most weekends", detail: "I follow a club", score: 2),
                .init(text: "All of it", detail: "Match of the Day is appointment TV", score: 3)
            ]
        ),
        SurveyQuestion(
            id: 2,
            kind: .knowledge,
            prompt: "How long have you been playing fantasy football?",
            subtitle: "The game where you pick 15 players under a £100m budget.",
            options: [
                .init(text: "This is my first time", detail: nil, score: 0),
                .init(text: "A season or two", detail: "I forget to set my team", score: 1),
                .init(text: "Several seasons", detail: "I check price changes", score: 2),
                .init(text: "Every season, chasing rank", detail: "Mini-league is war", score: 3)
            ]
        ),
        SurveyQuestion(
            id: 3,
            kind: .knowledge,
            prompt: "How much of the fantasy stats language do you already speak?",
            subtitle: "Pick the line that sounds familiar. Every term is explained below, and you can read the full list any time.",
            showsGlossary: true,
            options: [
                .init(text: "None of it",
                      detail: "The jargon loses me — explain things as you go",
                      score: 0),
                .init(text: "Clean sheets and bonus points",
                      detail: "Clean sheet: your team concedes nothing all match. Bonus: 1–3 extra points the game hands to the best performers.",
                      score: 1),
                .init(text: "Those, plus xG and xA",
                      detail: "xG (expected goals) and xA (expected assists) measure how good a player's chances were, whether or not they were scored.",
                      score: 2),
                .init(text: "All of it — FDR, EO, price changes",
                      detail: "FDR: fixture difficulty, 1 easy to 5 hard. EO: effective ownership, how exposed you are to a player. Prices move as managers buy and sell.",
                      score: 3)
            ]
        ),
        SurveyQuestion(
            id: 4,
            kind: .knowledge,
            prompt: "Could you name who takes penalties for most clubs?",
            subtitle: "Set-piece duty is where a lot of fantasy points hide.",
            options: [
                .init(text: "Not a chance", detail: nil, score: 0),
                .init(text: "A couple of the big ones", detail: nil, score: 1),
                .init(text: "Most of them", detail: nil, score: 2),
                .init(text: "Penalties, free kicks and corners", detail: nil, score: 3)
            ]
        ),
        SurveyQuestion(
            id: 5,
            kind: .control,
            prompt: "How much do you want to decide yourself?",
            subtitle: "You can change this later at any point.",
            options: [
                .init(text: "Nothing — just hand me a team", detail: "I'll trust the numbers", score: 0),
                .init(text: "Budget and my favourite clubs", detail: "The rest is on you", score: 1),
                .init(text: "Everything", detail: "Risk, fixtures, must-haves, blocklist", score: 2)
            ]
        )
    ]

    static func evaluate(answers: [Int]) -> SurveyResult {
        var raw = 0.0
        var maximum = 0.0
        for (index, question) in questions.enumerated() where question.kind == .knowledge {
            guard index < answers.count else { continue }
            raw += Double(question.options[answers[index]].score)
            maximum += 3
        }
        let knowledge = maximum > 0 ? Int(((raw / maximum) * 100).rounded()) : 0

        let controlIndex = questions.firstIndex(where: { $0.kind == .control }) ?? answers.count - 1
        let control = controlIndex < answers.count ? answers[controlIndex] : 1
        var recommended: SkillMode
        switch control {
        case 0: recommended = .auto
        case 1: recommended = .guided
        default: recommended = knowledge < 30 ? .guided : .expert
        }
        // Someone who knows the game well but asked for full auto still gets
        // full auto — intent wins. The reverse gets a gentle downgrade above.

        let statusIndex = questions.firstIndex(where: { $0.kind == .teamStatus }) ?? 0
        let statusAnswer = statusIndex < answers.count ? answers[statusIndex] : 0
        let teamStatus: TeamStatus = [.none, .importByID, .manual][min(statusAnswer, 2)]

        return SurveyResult(knowledge: knowledge, recommended: recommended, teamStatus: teamStatus)
    }
}

struct SurveyView: View {
    @EnvironmentObject var state: AppState
    @State private var index = 0
    @State private var answers: [Int] = []
    @State private var result: SurveyResult?
    @State private var chosenMode: SkillMode = .auto
    @State private var showingGlossary = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let result {
                resultScreen(result)
            } else {
                questionScreen
            }
        }
        .sheet(isPresented: $showingGlossary) { GlossaryView() }
        .animation(.easeInOut(duration: 0.25), value: index)
        .animation(.easeInOut(duration: 0.25), value: result)
    }

    // MARK: - Questions

    private var questionScreen: some View {
        let question = SurveyContent.questions[index]
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 6) {
                    ForEach(SurveyContent.questions.indices, id: \.self) { step in
                        Capsule()
                            .fill(step <= index ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.18)))
                            .frame(height: 4)
                    }
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Question \(index + 1) of \(SurveyContent.questions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.mint)
                    Text(question.prompt)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(question.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    if question.showsGlossary {
                        Button {
                            showingGlossary = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "book.fill")
                                Text("What do these mean?")
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

                VStack(spacing: 12) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { position, option in
                        Button {
                            answer(position)
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.text)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let detail = option.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.6))
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if index > 0 {
                    Button {
                        index -= 1
                        if answers.count > index { answers.removeLast(answers.count - index) }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
    }

    private func answer(_ option: Int) {
        if answers.count > index {
            answers[index] = option
        } else {
            answers.append(option)
        }
        if index == SurveyContent.questions.count - 1 {
            let evaluated = SurveyContent.evaluate(answers: answers)
            chosenMode = evaluated.recommended
            result = evaluated
        } else {
            index += 1
        }
    }

    // MARK: - Result

    private func resultScreen(_ result: SurveyResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(result.label.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.mint)
                    Text("Here's how I'd run it for you")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("Based on your answers I'd suggest **\(result.recommended.title)**. Change it if you disagree — nothing here is locked in.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                KnowledgeMeter(score: result.knowledge)

                if result.teamStatus.hasTeam {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Theme.mint)
                        Text("Next I'll ask for your existing squad, then suggest transfers from it.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .card()
                }

                VStack(spacing: 12) {
                    ForEach(SkillMode.allCases) { mode in
                        ModeCard(mode: mode,
                                 selected: chosenMode == mode,
                                 recommended: result.recommended == mode) {
                            chosenMode = mode
                        }
                    }
                }

                Button("Continue") {
                    state.completeSurvey(result, mode: chosenMode)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)

                Button {
                    showingGlossary = true
                } label: {
                    Label("Read the jargon buster", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }
}

struct KnowledgeMeter: View {
    let score: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Football knowledge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(score)/100")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.mint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(Theme.accentGradient)
                        .frame(width: max(8, geo.size.width * CGFloat(score) / 100))
                }
            }
            .frame(height: 10)
        }
        .card()
    }
}

struct ModeCard: View {
    let mode: SkillMode
    let selected: Bool
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.deepPurple : .white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(selected ? AnyShapeStyle(Theme.accentGradient)
                                               : AnyShapeStyle(Color.white.opacity(0.12)))
                    )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(mode.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if recommended {
                            Text("SUGGESTED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.mint.opacity(0.22)))
                                .foregroundStyle(Theme.mint)
                        }
                    }
                    Text(mode.blurb)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Theme.mint : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
