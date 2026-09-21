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
        detailLines(eventDetected: false)
    }

    func detailLines(eventDetected: Bool) -> [String] {
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
        if eventDetected {
            lines.append("Event/costume: visible form confirmed by a calibrated rule (beta)")
        } else if matchedSpecies.hasEventCostumeVariant {
            lines.append("Event/costume: variants exist for this species; the visible form is not confirmed yet")
        } else {
            lines.append("Event/costume: no variant in the current snapshot; still verify manually")
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

    static func canonicalSpeciesName(fromResourceLabel observedValue: String) -> String? {
        PokemonSpeciesCatalog.shared.profile(fromResourceLabel: observedValue)?.germanName
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
        for normalizedName in Self.ocrNormalizedCandidates(name) {
            if let exactMatch = entriesByNormalizedName[normalizedName] {
                return exactMatch
            }

            // Pokémon GO names can contain numeric IV annotations appended by the
            // player (including superscript/circled digits). Accept only a numeric
            // suffix and prefer the longest alias so e.g. Mewtwo never becomes Mew.
            // Vision occasionally reads a circled digit as O/I/l; accept only a
            // very short suffix made exclusively from those numeric lookalikes.
            for alias in aliasesByDescendingLength where normalizedName.hasPrefix(alias) {
                let suffix = normalizedName.dropFirst(alias.count)
                guard !suffix.isEmpty, suffix.count <= 8,
                      suffix.allSatisfy({ $0.isNumber || $0 == "o" || $0 == "i" || $0 == "l" }) else { continue }
                return entriesByNormalizedName[alias]
            }

            if let annotatedMatch = uniquelyMatchedAnnotatedPrefix(normalizedName) {
                return annotatedMatch
            }
        }

        return nil
    }

    func profile(fromResourceLabel label: String) -> PokemonSpeciesProfile? {
        // The candy/resource row is lower on the details card and remains
        // readable when a decorated nickname confuses OCR on the name row.
        // Match only explicit resource labels so arbitrary text cannot become
        // a species result.
        for normalizedLabel in Self.ocrNormalizedCandidates(label) {
            for alias in aliasesByDescendingLength {
                guard let aliasRange = normalizedLabel.range(of: alias) else { continue }
                let prefix = normalizedLabel[..<aliasRange.lowerBound]
                let suffix = normalizedLabel[aliasRange.upperBound...]
                guard prefix.count <= 5, prefix.allSatisfy(\.isNumber) else { continue }
                guard suffix.hasPrefix("bonbon") || suffix.hasPrefix("candy") else { continue }
                return entriesByNormalizedName[alias]
            }
        }

        return nil
    }

    private func uniquelyMatchedAnnotatedPrefix(_ observedName: String) -> PokemonSpeciesProfile? {
        var matchesByID: [Int: PokemonSpeciesProfile] = [:]

        for alias in aliasesByDescendingLength {
            var commonPrefixLength = 0
            for (observedCharacter, aliasCharacter) in zip(observedName, alias) {
                guard observedCharacter == aliasCharacter else { break }
                commonPrefixLength += 1
            }

            guard commonPrefixLength >= 6,
                  alias.count - commonPrefixLength <= 2 else { continue }

            let annotationArtifact = observedName.dropFirst(commonPrefixLength)
            guard annotationArtifact.count <= 8,
                  annotationArtifact.allSatisfy({
                      $0.isNumber || $0 == "o" || $0 == "i" || $0 == "l" || $0 == "q" || $0 == "d"
                  }),
                  let profile = entriesByNormalizedName[alias] else { continue }
            matchesByID[profile.id] = profile
        }

        guard matchesByID.count == 1 else { return nil }
        return matchesByID.values.first
    }

    private static func ocrNormalizedCandidates(_ value: String) -> [String] {
        let normalized = normalize(removingTrailingNumericAnnotations(from: value))
        let zeroAsLetterO = normalized.replacingOccurrences(of: "0", with: "o")
        return zeroAsLetterO == normalized ? [normalized] : [normalized, zeroAsLetterO]
    }

    private static func removingTrailingNumericAnnotations(from value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var endIndex = scalars.count
        var foundNumber = false
        let wrappers = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "·•◦"))

        while endIndex > 0 {
            let scalar = scalars[endIndex - 1]
            if isNumericAnnotation(scalar) {
                foundNumber = true
                endIndex -= 1
            } else if wrappers.contains(scalar) {
                endIndex -= 1
            } else {
                break
            }
        }

        guard foundNumber else { return value }
        return String(String.UnicodeScalarView(scalars[..<endIndex]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNumericAnnotation(_ scalar: Unicode.Scalar) -> Bool {
        if Character(String(scalar)).isNumber {
            return true
        }

        // Explicitly cover superscript/subscript and all common enclosed,
        // parenthesized, double-circled and filled-circled digit blocks. Some
        // of these are classified as symbols rather than decimal digits.
        switch scalar.value {
        case 0x00B2, 0x00B3, 0x00B9,
             0x2070, 0x2074...0x2079,
             0x2080...0x2089,
             0x2460...0x24FF,
             0x2776...0x2793,
             0x3251...0x325F,
             0x32B1...0x32BF:
            return true
        default:
            return false
        }
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
