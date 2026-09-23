import CoreImage
import CoreVideo
import Foundation

struct PokemonIVs: Equatable, Sendable {
    let attack: Int
    let defense: Int
    let stamina: Int

    var percentage: Int {
        Int((Double(attack + defense + stamina) / 45.0 * 100.0).rounded())
    }

    var summary: String {
        "IV \(attack)/\(defense)/\(stamina) · \(percentage)% beta"
    }

    var isPVPCandidate: Bool {
        // A conservative hint only: low Attack with strong bulk is a common
        // Great/Ultra League pattern; near-perfect IVs can matter in Master.
        (attack <= 5 && defense >= 12 && stamina >= 12)
            || (attack >= 14 && defense >= 14 && stamina >= 14)
    }
}

enum IVBarAnalyzer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private struct BarComponent {
        var startX: Int
        var endX: Int
        var lastMatchedX: Int
        var matchedPixelCount: Int
        var lastFilledX: Int?

        mutating func add(x: Int, isFilled: Bool) {
            endX = x
            lastMatchedX = x
            matchedPixelCount += 1
            if isFilled {
                lastFilledX = x
            }
        }
    }

    // Normalized centers measured from Pokemon GO's appraisal layout. Searching
    // around each center keeps this independent of the iPhone's pixel resolution.
    private static let expectedBarLayouts = [
        [0.750, 0.792, 0.835],
        [0.774, 0.817, 0.859]
    ]

    static func analyze(pixelBuffer: CVPixelBuffer) -> PokemonIVs? {
        guard let bgraPixelBuffer = makeBGRAPixelBuffer(from: pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(bgraPixelBuffer)
        let height = CVPixelBufferGetHeight(bgraPixelBuffer)
        guard width > 0, height > 0 else { return nil }

        guard CVPixelBufferLockBaseAddress(bgraPixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(bgraPixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(bgraPixelBuffer) else { return nil }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(bgraPixelBuffer)

        for layout in expectedBarLayouts {
            let values = layout.compactMap { ratio in
                measureBar(
                    expectedYRatio: ratio,
                    width: width,
                    height: height,
                    bytesPerRow: bytesPerRow,
                    bytes: bytes
                )
            }

            if values.count == 3 {
                return PokemonIVs(attack: values[0], defense: values[1], stamina: values[2])
            }
        }

        return nil
    }

    private static func makeBGRAPixelBuffer(from source: CVPixelBuffer) -> CVPixelBuffer? {
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
        ciContext.render(sourceImage, to: destination)
        return destination
    }

    private static func measureBar(
        expectedYRatio: Double,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        bytes: UnsafePointer<UInt8>
    ) -> Int? {
        let minimumX = max(0, Int(Double(width) * 0.08))
        let maximumX = min(width - 1, Int(Double(width) * 0.55))
        let centerY = Int(Double(height) * expectedYRatio)
        let searchRadius = max(4, Int(Double(height) * 0.012))
        let minimumY = max(0, centerY - searchRadius)
        let maximumY = min(height - 1, centerY + searchRadius)
        let gapTolerance = max(4, Int(ceil(Double(width) * 0.012)))
        let minimumSpan = Int(Double(width) * 0.20)

        var bestComponent: BarComponent?

        for y in minimumY...maximumY {
            var currentComponent: BarComponent?

            for x in minimumX...maximumX {
                let offset = y * bytesPerRow + x * 4
                let blue = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let red = Int(bytes[offset + 2])
                let filled = isFilledBarPixel(red: red, green: green, blue: blue)
                let track = isUnfilledTrackPixel(red: red, green: green, blue: blue)

                guard filled || track else { continue }

                if var component = currentComponent,
                   x - component.lastMatchedX <= gapTolerance {
                    component.add(x: x, isFilled: filled)
                    currentComponent = component
                } else {
                    consider(
                        currentComponent,
                        minimumSpan: minimumSpan,
                        bestComponent: &bestComponent
                    )
                    currentComponent = BarComponent(
                        startX: x,
                        endX: x,
                        lastMatchedX: x,
                        matchedPixelCount: 1,
                        lastFilledX: filled ? x : nil
                    )
                }
            }

            consider(
                currentComponent,
                minimumSpan: minimumSpan,
                bestComponent: &bestComponent
            )
        }

        guard let bestComponent else { return nil }
        guard let lastFilledX = bestComponent.lastFilledX else { return 0 }

        let totalWidth = max(1, bestComponent.endX - bestComponent.startX)
        let filledWidth = max(0, lastFilledX - bestComponent.startX)
        let rawValue = 15.0 * Double(filledWidth) / Double(totalWidth)
        return min(15, max(0, Int(rawValue.rounded())))
    }

    private static func consider(
        _ component: BarComponent?,
        minimumSpan: Int,
        bestComponent: inout BarComponent?
    ) {
        guard let component, component.endX - component.startX >= minimumSpan else { return }

        if bestComponent == nil
            || component.matchedPixelCount > bestComponent!.matchedPixelCount {
            bestComponent = component
        }
    }

    private static func isFilledBarPixel(red: Int, green: Int, blue: Int) -> Bool {
        let redBar = red >= 175 && red <= 245
            && green >= 80 && green <= 190
            && blue >= 70 && blue <= 175
            && red - green >= 25
            && red - blue >= 20

        let orangeBar = red >= 190
            && green >= 110 && green <= 205
            && blue >= 45 && blue <= 145
            && red - blue >= 55

        return redBar || orangeBar
    }

    private static func isUnfilledTrackPixel(red: Int, green: Int, blue: Int) -> Bool {
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        return minimum >= 190 && maximum <= 245 && maximum - minimum <= 10
    }
}
