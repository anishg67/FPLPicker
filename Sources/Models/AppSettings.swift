import SwiftUI

/// The app's accent pair. Everything tinted in the UI reads from this.
enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case mint, sky, sunset, magenta, lime

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mint: return "Mint"
        case .sky: return "Sky"
        case .sunset: return "Sunset"
        case .magenta: return "Magenta"
        case .lime: return "Lime"
        }
    }

    var primary: Color {
        switch self {
        case .mint: return Color(red: 0.00, green: 0.98, blue: 0.60)
        case .sky: return Color(red: 0.35, green: 0.78, blue: 1.00)
        case .sunset: return Color(red: 1.00, green: 0.72, blue: 0.30)
        case .magenta: return Color(red: 1.00, green: 0.44, blue: 0.78)
        case .lime: return Color(red: 0.78, green: 0.98, blue: 0.35)
        }
    }

    var secondary: Color {
        switch self {
        case .mint: return Color(red: 0.02, green: 0.87, blue: 0.98)
        case .sky: return Color(red: 0.55, green: 0.60, blue: 1.00)
        case .sunset: return Color(red: 1.00, green: 0.45, blue: 0.42)
        case .magenta: return Color(red: 0.72, green: 0.48, blue: 1.00)
        case .lime: return Color(red: 0.35, green: 0.90, blue: 0.65)
        }
    }
}

/// How much detail the player cards carry.
enum CardDetail: String, Codable, CaseIterable, Identifiable {
    case minimal, standard, full

    var id: String { rawValue }
    var name: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .full: return "Full"
        }
    }
    var detail: String {
        switch self {
        case .minimal: return "Names only — least clutter"
        case .standard: return "Name, club and price"
        case .full: return "Everything, plus projected points on the pitch"
        }
    }
    var showsPrice: Bool { self != .minimal }
    var showsProjection: Bool { self == .full }
}

/// App-wide preferences that aren't about any one squad.
struct AppSettings: Codable, Equatable {
    var accent: AccentTheme = .mint
    var showPlayerPhotos = true
    var cardDetail: CardDetail = .standard
    var showOwnership = false
    /// Budget used when the app picks a squad without being told otherwise.
    var defaultBudgetTenths = 1000
    /// Ask before a rebuild throws away hand-made edits.
    var confirmBeforeRebuild = true

    static let `default` = AppSettings()
}
