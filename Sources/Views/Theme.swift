import SwiftUI

enum Theme {
    /// Set from Settings. Static so the whole tree picks it up without every
    /// view having to thread a colour through.
    static var accent: AccentTheme = .mint

    static let purple = Color(red: 0.21, green: 0.02, blue: 0.31)
    static let deepPurple = Color(red: 0.13, green: 0.01, blue: 0.20)
    /// Named for the original palette; follows whatever accent is selected.
    static var mint: Color { accent.primary }
    static var cyan: Color { accent.secondary }
    static let pitchTop = Color(red: 0.03, green: 0.42, blue: 0.24)
    static let pitchBottom = Color(red: 0.02, green: 0.28, blue: 0.16)

    static var background: LinearGradient {
        LinearGradient(colors: [deepPurple, purple], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [mint, cyan], startPoint: .leading, endPoint: .trailing)
    }

    /// Primary shirt colour per club, keyed by the API's short name.
    static func clubColor(_ shortName: String) -> Color {
        switch shortName.uppercased() {
        case "ARS": return Color(red: 0.94, green: 0.11, blue: 0.16)
        case "AVL": return Color(red: 0.42, green: 0.09, blue: 0.25)
        case "BOU": return Color(red: 0.85, green: 0.10, blue: 0.13)
        case "BRE": return Color(red: 0.91, green: 0.15, blue: 0.16)
        case "BHA": return Color(red: 0.0, green: 0.34, blue: 0.71)
        case "BUR": return Color(red: 0.42, green: 0.10, blue: 0.25)
        case "CHE": return Color(red: 0.02, green: 0.15, blue: 0.60)
        case "COV": return Color(red: 0.34, green: 0.71, blue: 0.91)
        case "HUL": return Color(red: 0.94, green: 0.55, blue: 0.13)
        case "CRY": return Color(red: 0.10, green: 0.28, blue: 0.60)
        case "EVE": return Color(red: 0.0, green: 0.20, blue: 0.55)
        case "FUL": return Color(red: 0.10, green: 0.10, blue: 0.12)
        case "IPS": return Color(red: 0.20, green: 0.32, blue: 0.65)
        case "LEE": return Color(red: 0.98, green: 0.80, blue: 0.10)
        case "LEI": return Color(red: 0.0, green: 0.32, blue: 0.63)
        case "LIV": return Color(red: 0.78, green: 0.05, blue: 0.13)
        case "MCI": return Color(red: 0.42, green: 0.75, blue: 0.90)
        case "MUN": return Color(red: 0.85, green: 0.09, blue: 0.13)
        case "NEW": return Color(red: 0.15, green: 0.15, blue: 0.17)
        case "NFO": return Color(red: 0.87, green: 0.13, blue: 0.13)
        case "SOU": return Color(red: 0.84, green: 0.06, blue: 0.14)
        case "SUN": return Color(red: 0.90, green: 0.10, blue: 0.14)
        case "TOT": return Color(red: 0.07, green: 0.09, blue: 0.30)
        case "WHU": return Color(red: 0.49, green: 0.05, blue: 0.19)
        case "WOL": return Color(red: 0.98, green: 0.71, blue: 0.13)
        default: return Color(red: 0.35, green: 0.35, blue: 0.42)
        }
    }
}

/// Standard translucent card used across the app.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// Filled pill button in the app's accent gradient.
///
/// The body is a nested view rather than inline so it can read the accent from
/// the environment — a ButtonStyle's `makeBody` isn't re-run when a static
/// changes, so the colour would otherwise stay stale until the button itself did.
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        AccentButtonBody(configuration: configuration, enabled: enabled)
    }

    struct AccentButtonBody: View {
        let configuration: Configuration
        let enabled: Bool
        @Environment(\.accentTheme) private var accent

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Theme.deepPurple)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule().fill(enabled
                        ? AnyShapeStyle(LinearGradient(colors: [accent.primary, accent.secondary],
                                                       startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.2)))
                )
                .opacity(configuration.isPressed ? 0.75 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

// MARK: - Display settings passed down the view tree

private struct AccentThemeKey: EnvironmentKey { static let defaultValue = AccentTheme.mint }
private struct ShowPlayerPhotosKey: EnvironmentKey { static let defaultValue = true }
private struct CardDetailKey: EnvironmentKey { static let defaultValue = CardDetail.standard }
private struct ShowOwnershipKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var accentTheme: AccentTheme {
        get { self[AccentThemeKey.self] }
        set { self[AccentThemeKey.self] = newValue }
    }
    var showsPlayerPhotos: Bool {
        get { self[ShowPlayerPhotosKey.self] }
        set { self[ShowPlayerPhotosKey.self] = newValue }
    }
    var cardDetail: CardDetail {
        get { self[CardDetailKey.self] }
        set { self[CardDetailKey.self] = newValue }
    }
    var showsOwnership: Bool {
        get { self[ShowOwnershipKey.self] }
        set { self[ShowOwnershipKey.self] = newValue }
    }
}
