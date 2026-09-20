import Foundation

enum PokemonRarity: String, Decodable, Equatable, Sendable {
    case standard
    case legendary
    case mythical
    case ultraBeast
    case unknown

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .legendary: return "Legendary"
        case .mythical: return "Mythical"
        case .ultraBeast: return "Ultra Beast"
        case .unknown: return "Unknown rarity"
        }
    }

    var isProtectedClass: Bool {
        self == .legendary || self == .mythical || self == .ultraBeast
    }
}

struct PokemonSpeciesProfile: Decodable, Equatable, Sendable {
    let id: Int
    let englishName: String
    let germanName: String
    let rarity: PokemonRarity
    let shinyReleased: Bool
    let hasEventCostumeVariant: Bool
}

struct PokemonProtectionAssessment: Equatable, Sendable {
    enum TransferAdvice: Equatable, Sendable {
        case doNotTransfer
        case manualReview
    }

    let matchedSpecies: PokemonSpeciesProfile?
    let transferAdvice: TransferAdvice

    var rarity: PokemonRarity {
        matchedSpecies?.rarity ?? .unknown
    }

    var headline: String {
        switch transferAdvice {
        case .doNotTransfer:
            return "Do not transfer"
        case .manualReview:
            return "Check before transfer"
        }
    }

    var symbolName: String {
        transferAdvice == .doNotTransfer ? "hand.raised.fill" : "exclamationmark.triangle.fill"
    }

    var compactSummary: String {
        guard let matchedSpecies else {
            return "⚠️ Species unknown — check manually"
        }

        if matchedSpecies.rarity.isProtectedClass {
            return "⛔ \(matchedSpecies.rarity.label) — do not transfer"
        }

        if matchedSpecies.shinyReleased && matchedSpecies.hasEventCostumeVariant {
            return "⚠️ Shiny + event variants possible — not confirmed"
        }

        if matchedSpecies.hasEventCostumeVariant {
            return "⚠️ Event/costume variant possible — not confirmed"
        }

        if matchedSpecies.shinyReleased {
            return "⚠️ Shiny released for species — not confirmed"
        }

        return "⚠️ Check manually before transfer"
    }

    var detailLines: [String] {
        guard let matchedSpecies else {
            return [
                "Species not matched in the offline catalog (possibly a nickname or OCR error).",
                "Shiny and event state are unconfirmed."
            ]
        }

        var lines = [
            matchedSpecies.rarity == .standard
                ? "Rarity: not classified as Legendary, Mythical, or Ultra Beast"
                : "Protected rarity class: \(matchedSpecies.rarity.label)"
        ]
        lines.append(
            matchedSpecies.shinyReleased
                ? "Shiny: released for this species; the visible Shiny symbol is not confirmed yet"
                : "Shiny: not listed in the current snapshot; treat as unconfirmed"
        )
        lines.append(
            matchedSpecies.hasEventCostumeVariant
                ? "Event/costume: variants exist for this species; the visible form is not confirmed yet"
                : "Event/costume: no variant in the current snapshot; still verify manually"
        )

        if matchedSpecies.shinyReleased && matchedSpecies.hasEventCostumeVariant {
            lines.append("Combination warning: this species can have Shiny + event variants")
        }

        return lines
    }
}

enum PokemonProtection {
    static func isKnownSpeciesName(_ value: String) -> Bool {
        PokemonSpeciesCatalog.shared.profile(named: value) != nil
    }

    static func canonicalSpeciesName(from observedValue: String) -> String? {
        PokemonSpeciesCatalog.shared.profile(named: observedValue)?.germanName
    }

    static func assess(pokemonName: String?) -> PokemonProtectionAssessment {
        guard let pokemonName, let profile = PokemonSpeciesCatalog.shared.profile(named: pokemonName) else {
            return PokemonProtectionAssessment(matchedSpecies: nil, transferAdvice: .manualReview)
        }

        return PokemonProtectionAssessment(
            matchedSpecies: profile,
            transferAdvice: profile.rarity.isProtectedClass ? .doNotTransfer : .manualReview
        )
    }
}

private struct PokemonCatalogSnapshot: Decodable {
    let schemaVersion: Int
    let species: [PokemonSpeciesProfile]
}

private final class PokemonSpeciesCatalog: @unchecked Sendable {
    static let shared = PokemonSpeciesCatalog()

    private let entriesByNormalizedName: [String: PokemonSpeciesProfile]
    private let aliasesByDescendingLength: [String]

    private init(bundle: Bundle = .main) {
        guard
            let url = bundle.url(forResource: "pokemon_catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(PokemonCatalogSnapshot.self, from: data),
            snapshot.schemaVersion == 1
        else {
            entriesByNormalizedName = [:]
            aliasesByDescendingLength = []
            return
        }

        var aliases: [String: PokemonSpeciesProfile] = [:]
        for entry in snapshot.species {
            aliases[Self.normalize(entry.englishName)] = entry
            aliases[Self.normalize(entry.germanName)] = entry
        }
        entriesByNormalizedName = aliases
        aliasesByDescendingLength = aliases.keys.sorted {
            if $0.count == $1.count { return $0 < $1 }
            return $0.count > $1.count
        }
    }

    func profile(named name: String) -> PokemonSpeciesProfile? {
        let normalizedName = Self.normalize(name)
        if let exactMatch = entriesByNormalizedName[normalizedName] {
            return exactMatch
        }

        // Pokémon GO names can contain numeric IV annotations appended by the
        // player (including superscript/circled digits). Accept only a numeric
        // suffix and prefer the longest alias so e.g. Mewtwo never becomes Mew.
        for alias in aliasesByDescendingLength where normalizedName.hasPrefix(alias) {
            let suffix = normalizedName.dropFirst(alias.count)
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) else { continue }
            return entriesByNormalizedName[alias]
        }

        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "♀", with: " female ")
            .replacingOccurrences(of: "♂", with: " male ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { String($0) }
            .joined()
            .lowercased()
    }
}
