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

enum PokeAssistActivitySize: String, Codable, Hashable {
    case xxs
    case xxl
    case none
}

struct PokeAssistActivityPresentation: Codable, Hashable {
    var mode: PokeAssistActivityMode
    var pokemonName: String?
    var combatPower: Int?
    // Optional so activities persisted by earlier builds still decode.
    var combatPowerIsCached: Bool?
    var ivAttack: Int?
    var ivDefense: Int?
    var ivStamina: Int?
    var ivPercentage: Int?
    var shinyDetected: Bool
    var eventDetected: Bool
    var rarity: PokeAssistActivityRarity
    var size: PokeAssistActivitySize
    var dynamaxDetected: Bool
    var pvpCandidate: Bool

    static let scanning = PokeAssistActivityPresentation(
        mode: .scanning,
        pokemonName: nil,
        combatPower: nil,
        combatPowerIsCached: false,
        ivAttack: nil,
        ivDefense: nil,
        ivStamina: nil,
        ivPercentage: nil,
        shinyDetected: false,
        eventDetected: false,
        rarity: .unknown,
        size: .none,
        dynamaxDetected: false,
        pvpCandidate: false
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
