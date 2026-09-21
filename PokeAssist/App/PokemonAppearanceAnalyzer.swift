import CoreImage
import CoreVideo
import Foundation

struct PokemonAppearanceObservation: Equatable, Sendable {
    let pokemonName: String
    let shinyDetected: Bool
    let eventDetected: Bool
}

/// Conservatively confirms visible traits for calibrated species.
///
/// A sparkling background is deliberately not sufficient evidence: several
/// normal Pokémon use animated or glittering backgrounds. Each rule below is
/// tied to a species and to a visible colour/form difference observed on a
/// real Pokémon GO detail screen. Unsupported species remain unknown.
final class PokemonAppearanceAnalyzer: @unchecked Sendable {
    private enum SpeciesRule {
        case rowlet
        case hoothoot
        case pikachu
    }

    private struct Region {
        let minimumX: Double
        let maximumX: Double
        let minimumY: Double
        let maximumY: Double
    }

    private struct ColorRatios {
        var total = 0
        var dark = 0
        var nearBlack = 0
        var white = 0
        var red = 0
        var orange = 0
        var yellow = 0
        var teal = 0

        private func ratio(_ value: Int) -> Double {
            guard total > 0 else { return 0 }
            return Double(value) / Double(total)
        }

        var darkRatio: Double { ratio(dark) }
        var nearBlackRatio: Double { ratio(nearBlack) }
        var whiteRatio: Double { ratio(white) }
        var redRatio: Double { ratio(red) }
        var orangeRatio: Double { ratio(orange) }
        var yellowRatio: Double { ratio(yellow) }
        var tealRatio: Double { ratio(teal) }
    }

    private let analysisQueue = DispatchQueue(label: "de.schroeder.PokeAssist.appearance", qos: .userInitiated)
    private let stateLock = NSLock()
    private let minimumAnalysisInterval: TimeInterval = 0.18

    private var isAnalyzing = false
    private var lastAnalysisDate = Date.distantPast

    func submit(
        pixelBuffer: CVPixelBuffer,
        pokemonName: String,
        completion: @escaping @Sendable (PokemonAppearanceObservation) -> Void
    ) {
        guard let rule = Self.rule(for: pokemonName) else { return }

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
            let observation = analyze(pixelBuffer: pixelBuffer, pokemonName: pokemonName, rule: rule)

            stateLock.lock()
            isAnalyzing = false
            stateLock.unlock()

            completion(observation)
        }
    }

    private func analyze(
        pixelBuffer: CVPixelBuffer,
        pokemonName: String,
        rule: SpeciesRule
    ) -> PokemonAppearanceObservation {
        guard let bgraPixelBuffer = makeBGRAPixelBuffer(from: pixelBuffer) else {
            return PokemonAppearanceObservation(
                pokemonName: pokemonName,
                shinyDetected: false,
                eventDetected: false
            )
        }

        guard CVPixelBufferLockBaseAddress(bgraPixelBuffer, .readOnly) == kCVReturnSuccess else {
            return PokemonAppearanceObservation(
                pokemonName: pokemonName,
                shinyDetected: false,
                eventDetected: false
            )
        }
        defer { CVPixelBufferUnlockBaseAddress(bgraPixelBuffer, .readOnly) }

        switch rule {
        case .rowlet:
            // Shiny Bauz/Rowlet has a distinctive turquoise body. Requiring
            // both the pale face and red feet/beak prevents green backgrounds
            // alone from satisfying the rule.
            let body = sample(
                bgraPixelBuffer,
                region: Region(minimumX: 0.40, maximumX: 0.60, minimumY: 0.265, maximumY: 0.355)
            )
            let shiny = body.tealRatio >= 0.18
                && body.whiteRatio >= 0.15
                && body.redRatio >= 0.01
            return PokemonAppearanceObservation(
                pokemonName: pokemonName,
                shinyDetected: shiny,
                eventDetected: false
            )

        case .hoothoot:
            // Shiny Hoothoot is gold rather than brown. The lower body is
            // sampled separately from the hat so Shiny and costume can be
            // reported independently.
            let lowerBody = sample(
                bgraPixelBuffer,
                region: Region(minimumX: 0.40, maximumX: 0.60, minimumY: 0.285, maximumY: 0.355)
            )
            let hat = sample(
                bgraPixelBuffer,
                region: Region(minimumX: 0.43, maximumX: 0.57, minimumY: 0.190, maximumY: 0.245)
            )
            let shiny = lowerBody.yellowRatio >= 0.20
                && lowerBody.whiteRatio >= 0.16
                && lowerBody.redRatio + lowerBody.orangeRatio <= 0.14
            let event = hat.darkRatio >= 0.12
                && hat.yellowRatio + hat.orangeRatio >= 0.30
            return PokemonAppearanceObservation(
                pokemonName: pokemonName,
                shinyDetected: shiny,
                eventDetected: event
            )

        case .pikachu:
            // The calibrated New Year's Pikachu wears a broad black top hat.
            // Normal Pikachu's black ear tips sit outside this central region.
            let hat = sample(
                bgraPixelBuffer,
                region: Region(minimumX: 0.43, maximumX: 0.57, minimumY: 0.190, maximumY: 0.245)
            )
            let event = hat.nearBlackRatio >= 0.18 && hat.yellowRatio >= 0.05
            return PokemonAppearanceObservation(
                pokemonName: pokemonName,
                shinyDetected: false,
                eventDetected: event
            )
        }
    }

    private func sample(_ pixelBuffer: CVPixelBuffer, region: Region) -> ColorRatios {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > width,
              let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return ColorRatios() }

        let minimumX = max(0, Int(Double(width) * region.minimumX))
        let maximumX = min(width, Int(Double(width) * region.maximumX))
        let minimumY = max(0, Int(Double(height) * region.minimumY))
        let maximumY = min(height, Int(Double(height) * region.maximumY))
        guard minimumX < maximumX, minimumY < maximumY else { return ColorRatios() }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var result = ColorRatios()

        // Every second pixel is sufficient for the broad colour/form signals
        // and keeps repeated on-device analysis inexpensive.
        for y in stride(from: minimumY, to: maximumY, by: 2) {
            for x in stride(from: minimumX, to: maximumX, by: 2) {
                let offset = y * bytesPerRow + x * 4
                let blue = Double(bytes[offset]) / 255
                let green = Double(bytes[offset + 1]) / 255
                let red = Double(bytes[offset + 2]) / 255
                let maximum = max(red, max(green, blue))
                let minimum = min(red, min(green, blue))
                let delta = maximum - minimum
                let saturation = maximum > 0 ? delta / maximum : 0

                result.total += 1
                if maximum < 0.28 { result.dark += 1 }
                if maximum < 0.16 { result.nearBlack += 1 }
                if saturation < 0.14, maximum > 0.72 { result.white += 1 }

                guard saturation > 0.28, delta > 0 else { continue }
                let hue: Double
                if maximum == red {
                    hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
                } else if maximum == green {
                    hue = (((blue - red) / delta) + 2) / 6
                } else {
                    hue = (((red - green) / delta) + 4) / 6
                }
                let normalizedHue = hue < 0 ? hue + 1 : hue

                if normalizedHue < 0.045 || normalizedHue > 0.955 {
                    result.red += 1
                } else if normalizedHue < 0.11 {
                    result.orange += 1
                } else if normalizedHue < 0.19 {
                    result.yellow += 1
                } else if normalizedHue >= 0.42, normalizedHue < 0.58 {
                    result.teal += 1
                }
            }
        }

        return result
    }

    private static func rule(for pokemonName: String) -> SpeciesRule? {
        let normalized = pokemonName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()

        switch normalized {
        case "bauz", "rowlet": return .rowlet
        case "hoothoot": return .hoothoot
        case "pikachu": return .pikachu
        default: return nil
        }
    }

    private func makeBGRAPixelBuffer(from source: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA {
            return source
        }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else { return nil }

        let sourceImage = CIImage(cvPixelBuffer: source)
        CIContext(options: [.cacheIntermediates: false]).render(sourceImage, to: destination)
        return destination
    }
}
