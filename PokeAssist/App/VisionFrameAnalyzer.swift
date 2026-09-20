import CoreVideo
import Foundation
import ImageIO
import Vision

struct PokemonRecognition: Equatable, Sendable {
    enum Screen: String, Sendable {
        case appraisal
        case pokemonDetails
        case map
        case unknown
    }

    let screen: Screen
    let pokemonName: String?
    let combatPower: Int?
    let confidence: Double

    var summary: String {
        switch screen {
        case .appraisal:
            return joinedSummary(prefix: "Appraisal detected")
        case .pokemonDetails:
            return joinedSummary(prefix: "Pokémon detected")
        case .map:
            return "Map detected"
        case .unknown:
            return "Scanning Pokémon GO"
        }
    }

    private func joinedSummary(prefix: String) -> String {
        var parts = [prefix]

        if let pokemonName {
            parts.append(pokemonName)
        }

        if let combatPower {
            parts.append("CP " + String(combatPower))
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
    private let minimumAnalysisInterval: TimeInterval = 1.5

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

            return Self.classify(lines: lines)
        } catch {
            return PokemonRecognition(
                screen: .unknown,
                pokemonName: nil,
                combatPower: nil,
                confidence: 0
            )
        }
    }

    private static func classify(lines: [RecognizedLine]) -> PokemonRecognition {
        let normalizedText = lines
            .map(\.text)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()

        let appraisalKeywords = [
            "ANGRIFF", "VERTEIDIGUNG", "KRAFTPUNKTE", "BEWERTUNG",
            "ATTACK", "DEFENSE", "STAMINA", "APPRAISAL"
        ]
        let appraisalMatches = appraisalKeywords.filter { normalizedText.contains($0) }.count
        let combatPower = parseCombatPower(from: normalizedText)
        let pokemonName = findPokemonName(in: lines)

        let screen: PokemonRecognition.Screen
        if appraisalMatches >= 2 {
            screen = .appraisal
        } else if combatPower != nil {
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
            confidence: confidence
        )
    }

    private static func parseCombatPower(from text: String) -> Int? {
        let pattern = #"\b(?:CP|WP)\s*[:.]?\s*([0-9]{1,5})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = expression.firstMatch(in: text, range: range),
            let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int(text[valueRange])
    }

    private static func findPokemonName(in lines: [RecognizedLine]) -> String? {
        let excludedTerms = [
            "POKÉMON", "POKEMON", "POWER UP", "MORE POWER", "ENTWICKELN", "VERSCHICKEN",
            "BEWERTUNG", "ANGRIFF", "VERTEIDIGUNG", "KRAFTPUNKTE", "ATTACK", "DEFENSE",
            "STAMINA", "APPRAISAL", "CANDY", "BONBON", "STARDUST", "STERNENSTAUB"
        ]

        return lines
            .filter { line in
                let candidate = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = candidate.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                ).uppercased()
                let letters = candidate.unicodeScalars.filter(CharacterSet.letters.contains).count

                return line.boundingBox.midY > 0.52
                    && line.confidence >= 0.45
                    && letters >= 3
                    && candidate.count <= 24
                    && candidate.rangeOfCharacter(from: .decimalDigits) == nil
                    && !excludedTerms.contains(where: { normalized.contains($0) })
            }
            .sorted { lhs, rhs in
                if lhs.boundingBox.midY == rhs.boundingBox.midY {
                    return lhs.confidence > rhs.confidence
                }
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            .first?
            .text
    }
}
