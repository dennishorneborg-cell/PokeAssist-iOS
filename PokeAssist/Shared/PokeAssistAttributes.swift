import ActivityKit
import Foundation

enum PokeAssistActivityMode: String, Codable, Hashable {
    case scanning
    case pokemon
    case appraisal
}

enum PokeAssistActivityRarity: String, Codable, Hashable {
    case standard
    case legendary
    case mythical
    case ultraBeast
    case unknown

    var isProtected: Bool {
        self == .legendary || self == .mythical || self == .ultraBeast
    }
}

struct PokeAssistActivityPresentation: Codable, Hashable {
    var mode: PokeAssistActivityMode
    var pokemonName: String?
    var combatPower: Int?
    var ivAttack: Int?
    var ivDefense: Int?
    var ivStamina: Int?
    var ivPercentage: Int?
    var shinyDetected: Bool
    var rarity: PokeAssistActivityRarity

    static let scanning = PokeAssistActivityPresentation(
        mode: .scanning,
        pokemonName: nil,
        combatPower: nil,
        ivAttack: nil,
        ivDefense: nil,
        ivStamina: nil,
        ivPercentage: nil,
        shinyDetected: false,
        rarity: .unknown
    )
}

struct PokeAssistAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var frameCount: Int
        var status: String
        var recognitionSummary: String
        var presentation: PokeAssistActivityPresentation
    }

    var sessionName: String
}
