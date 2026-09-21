import CoreVideo
import Foundation
import ImageIO
import Vision

enum PokemonSizeClass: String, Equatable, Sendable {
    case xxs = "XXS"
    case xxl = "XXL"
}

struct PokemonRecognition: Equatable, Sendable {
    enum Screen: String, Sendable {
        case appraisal
        case pokemonDetails
        case map
        case pokeAssist
        case unknown
    }

    let screen: Screen
    let pokemonName: String?
    let combatPower: Int?
    let confidence: Double
    let observedText: String?
    let individualValues: PokemonIVs?
    let protection: PokemonProtectionAssessment
    let sizeClass: PokemonSizeClass?
    let isDynamax: Bool

    var isPokemonResult: Bool {
        screen == .appraisal || screen == .pokemonDetails
    }

    var summary: String {
        summary(shinyDetected: false)
    }

    func summary(shinyDetected: Bool) -> String {
        switch screen {
        case .appraisal:
            return joinedSummary(prefix: "Appraisal", shinyDetected: shinyDetected)
        case .pokemonDetails:
            return joinedSummary(prefix: "Pokémon", shinyDetected: shinyDetected)
        case .map:
            return "Map detected"
        case .pokeAssist:
            return "PokeAssist active"
        case .unknown:
            return "Scanning Pokémon GO"
        }
    }

    private func joinedSummary(prefix: String, shinyDetected: Bool) -> String {
        var parts: [String] = []

        if shinyDetected {
            parts.append("✨ Shiny detected (beta)")
        }

        if protection.rarity.isProtectedClass {
            parts.append("⛔ \(protection.rarity.label)")
        }

        parts.append(prefix)

        if let pokemonName {
            parts.append(pokemonName)
        }

        if let combatPower {
            parts.append("CP " + String(combatPower))
        }

        if let individualValues {
            parts.append(individualValues.summary)
            if individualValues.isPVPCandidate {
                parts.append("PvP IV pattern beta")
            }
        }

        if let sizeClass {
            parts.append(sizeClass.rawValue)
        }

        if isDynamax {
            parts.append("Dynamax")
        }

        return parts.joined(separator: " · ")
    }
}

final class VisionFrameAnalyzer: @unchecked Sendable {
    private struct RecognizedLine {
        let text: String
        let confidence: Float
        let boundingBox: CGRect
    }

    private let analysisQueue = DispatchQueue(label: "de.schroeder.PokeAssist.vision", qos: .utility)
    private let stateLock = NSLock()
    private let minimumAnalysisInterval: TimeInterval = 0.45

    private var isAnalyzing = false
    private var lastAnalysisDate = Date.distantPast

    func submit(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping @Sendable (PokemonRecognition) -> Void
    ) {
        let now = Date()

        stateLock.lock()
        guard !isAnalyzing, now.timeIntervalSince(lastAnalysisDate) >= minimumAnalysisInterval else {
            stateLock.unlock()
            return
        }
        isAnalyzing = true
        lastAnalysisDate = now
        stateLock.unlock()

        analysisQueue.async { [self] in
            let result = analyze(pixelBuffer: pixelBuffer)

            stateLock.lock()
            isAnalyzing = false
            stateLock.unlock()

            completion(result)
        }
    }

    private func analyze(pixelBuffer: CVPixelBuffer) -> PokemonRecognition {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.customWords = [
            "Pokémon", "Bewertung", "Angriff", "Verteidigung", "Kraftpunkte",
            "Appraisal", "Attack", "Defense", "Stamina"
        ]
        request.minimumTextHeight = 0.012

        do {
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )
            try handler.perform([request])

            let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(
                    text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }

            let recognition = Self.classify(lines: lines)
            guard recognition.screen == .appraisal else { return recognition }

            return PokemonRecognition(
                screen: recognition.screen,
                pokemonName: recognition.pokemonName,
                combatPower: recognition.combatPower,
                confidence: recognition.confidence,
                observedText: recognition.observedText,
                individualValues: IVBarAnalyzer.analyze(pixelBuffer: pixelBuffer),
                protection: recognition.protection,
                sizeClass: recognition.sizeClass,
                isDynamax: recognition.isDynamax
            )
        } catch {
            return PokemonRecognition(
                screen: .unknown,
                pokemonName: nil,
                combatPower: nil,
                confidence: 0,
                observedText: nil,
                individualValues: nil,
                protection: PokemonProtection.assess(pokemonName: nil),
                sizeClass: nil,
                isDynamax: false
            )
        }
    }

    private static func classify(lines: [RecognizedLine]) -> PokemonRecognition {
        // System overlays such as the expanded Dynamic Island are part of the
        // captured display. Classification uses only app content below that
        // overlay so PokeAssist cannot read its own previous "Appraisal" text.
        let contentLines = lines.filter { $0.boundingBox.midY < 0.82 }
        let normalizedText = contentLines
            .map(\.text)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()

        let appraisalKeywords = [
            "ANGRIFF", "VERTEIDIGUNG", "KRAFTPUNKTE", "BEWERTUNG",
            "ATTACK", "DEFENSE", "STAMINA", "APPRAISAL", "KP"
        ]
        let appraisalText = contentLines
            .filter { $0.boundingBox.midY < 0.50 }
            .map(\.text)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        let appraisalMatches = appraisalKeywords.filter { appraisalText.contains($0) }.count
        let combatPower = parseCombatPower(from: lines)
        let pokemonName = findPokemonName(in: lines)
        let observedText = makeObservedText(from: contentLines)
        let protection = PokemonProtection.assess(pokemonName: pokemonName)
        let sizeClass: PokemonSizeClass?
        if normalizedText.contains("XXL") {
            sizeClass = .xxl
        } else if normalizedText.contains("XXS") {
            sizeClass = .xxs
        } else {
            sizeClass = nil
        }
        let isDynamax = normalizedText.contains("DYNAMAX")
            || normalizedText.contains("GIGADYNAMAX")

        let screen: PokemonRecognition.Screen
        if normalizedText.contains("ON-DEVICE RECOGNITION")
            || normalizedText.contains("SCREEN CAPTURE") {
            screen = .pokeAssist
        } else if appraisalMatches >= 2 {
            screen = .appraisal
        } else if combatPower != nil || pokemonName != nil {
            screen = .pokemonDetails
        } else if normalizedText.contains("IN DER NÄHE") || normalizedText.contains("NEARBY") {
            screen = .map
        } else {
            screen = .unknown
        }

        let usefulLines = lines.filter { !$0.text.isEmpty }
        let confidence: Double
        if usefulLines.isEmpty {
            confidence = 0
        } else {
            confidence = Double(usefulLines.map(\.confidence).reduce(0, +)) / Double(usefulLines.count)
        }

        return PokemonRecognition(
            screen: screen,
            pokemonName: pokemonName,
            combatPower: combatPower,
            confidence: confidence,
            observedText: observedText,
            individualValues: nil,
            protection: protection,
            sizeClass: sizeClass,
            isDynamax: isDynamax
        )
    }

    private static func parseCombatPower(from lines: [RecognizedLine]) -> Int? {
        let pattern = #"\b(?:C\s*P|W\s*P)\s*[:.]?\s*([0-9]{1,2}(?:[.\s][0-9]{3})|[0-9]{1,5})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        let candidates = lines
            .filter { line in
                let compact = line.text
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .uppercased()
                    .filter { $0.isLetter || $0.isNumber }
                return line.boundingBox.midY > 0.78
                    && line.boundingBox.midY < 0.95
                    && (compact.hasPrefix("CP") || compact.hasPrefix("WP"))
            }
            .sorted { $0.confidence > $1.confidence }

        for candidate in candidates {
            let text = candidate.text.uppercased()
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = expression.firstMatch(in: text, range: range),
                  let valueRange = Range(match.range(at: 1), in: text) else { continue }

            let digits = text[valueRange].filter { $0.isNumber }
            if let value = Int(digits) {
                return value
            }
        }

        return nil
    }

    private static func findPokemonName(in lines: [RecognizedLine]) -> String? {
        let excludedTerms = [
            "POKÉMON", "POKEMON", "POWER UP", "MORE POWER", "ENTWICKELN", "VERSCHICKEN",
            "BEWERTUNG", "ANGRIFF", "VERTEIDIGUNG", "KRAFTPUNKTE", "ATTACK", "DEFENSE",
            "STAMINA", "APPRAISAL", "CANDY", "BONBON", "STARDUST", "STERNENSTAUB"
        ]

        let candidates = lines
            .filter { line in
                let candidate = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = candidate.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                ).uppercased()
                let letters = candidate.unicodeScalars.filter(CharacterSet.letters.contains).count
                let compact = normalized.replacingOccurrences(of: " ", with: "")

                // The Dynamic Island is captured with the display and may
                // contain PokeAssist's previous species name. Restrict name
                // matching to Pokémon GO's name-card band to avoid that
                // feedback loop while retaining normal and appraisal views.
                return line.boundingBox.midY > 0.50
                    && line.boundingBox.midY < 0.78
                    && line.confidence >= 0.32
                    && letters >= 3
                    && candidate.count <= 24
                    && !compact.hasPrefix("WP")
                    && !compact.hasPrefix("CP")
                    && !excludedTerms.contains(where: { normalized.contains($0) })
            }
            .sorted { lhs, rhs in
                if lhs.boundingBox.midY == rhs.boundingBox.midY {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }

        for candidate in candidates {
            if let canonicalName = PokemonProtection.canonicalSpeciesName(from: candidate.text) {
                return canonicalName
            }
        }

        return candidates.first?.text
    }

    private static func makeObservedText(from lines: [RecognizedLine]) -> String? {
        let text = lines
            .filter { !$0.text.isEmpty && $0.confidence >= 0.35 }
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .prefix(6)
            .map(\.text)
            .joined(separator: " · ")

        guard !text.isEmpty else { return nil }
        return String(text.prefix(120))
    }
}
