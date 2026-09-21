import CoreImage
import CoreVideo
import Foundation

struct ShinySparkleObservation: Equatable, Sendable {
    let candidateCount: Int
    let candidateBuckets: [Int]
    let validLayout: Bool
}

final class ShinySparkleAnalyzer: @unchecked Sendable {
    private let analysisQueue = DispatchQueue(label: "de.schroeder.PokeAssist.sparkles", qos: .utility)
    private let stateLock = NSLock()
    private let minimumAnalysisInterval: TimeInterval = 0.20

    private var isAnalyzing = false
    private var lastAnalysisDate = Date.distantPast

    func submit(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping @Sendable (ShinySparkleObservation) -> Void
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
            let observation = analyze(pixelBuffer: pixelBuffer)

            stateLock.lock()
            isAnalyzing = false
            stateLock.unlock()

            completion(observation)
        }
    }

    private func analyze(pixelBuffer: CVPixelBuffer) -> ShinySparkleObservation {
        guard let bgraPixelBuffer = makeBGRAPixelBuffer(from: pixelBuffer) else {
            return ShinySparkleObservation(candidateCount: 0, candidateBuckets: [], validLayout: false)
        }

        let width = CVPixelBufferGetWidth(bgraPixelBuffer)
        let height = CVPixelBufferGetHeight(bgraPixelBuffer)
        guard width > 0, height > width else {
            return ShinySparkleObservation(candidateCount: 0, candidateBuckets: [], validLayout: false)
        }

        guard CVPixelBufferLockBaseAddress(bgraPixelBuffer, .readOnly) == kCVReturnSuccess else {
            return ShinySparkleObservation(candidateCount: 0, candidateBuckets: [], validLayout: false)
        }
        defer { CVPixelBufferUnlockBaseAddress(bgraPixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(bgraPixelBuffer) else {
            return ShinySparkleObservation(candidateCount: 0, candidateBuckets: [], validLayout: false)
        }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(bgraPixelBuffer)

        // Pokémon GO places the animated Shiny sparkles around the sprite. The
        // two side bands avoid the mostly static bright Pokémon body, the CP
        // arc, the Dynamic Island, and the name/action card below.
        let minimumX = max(0, Int(Double(width) * 0.08))
        let maximumX = min(width - 1, Int(Double(width) * 0.82))
        let minimumY = max(0, Int(Double(height) * 0.13))
        let maximumY = min(height - 1, Int(Double(height) * 0.32))
        let cropWidth = maximumX - minimumX + 1
        let cropHeight = maximumY - minimumY + 1
        guard cropWidth > 0, cropHeight > 0 else {
            return ShinySparkleObservation(candidateCount: 0, candidateBuckets: [], validLayout: false)
        }

        var mask = [UInt8](repeating: 0, count: cropWidth * cropHeight)
        for y in minimumY...maximumY {
            for x in minimumX...maximumX {
                let normalizedX = Double(x) / Double(width)
                let normalizedY = Double(y) / Double(height)
                guard normalizedX <= 0.31
                    || normalizedX >= 0.69
                    || normalizedY <= 0.23 else { continue }

                let offset = y * bytesPerRow + x * 4
                let blue = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let red = Int(bytes[offset + 2])
                let maximum = max(red, max(green, blue))
                let minimum = min(red, min(green, blue))

                // Shiny animation cores are almost white. Warm fire particles
                // (such as normal Ponyta) are rejected by the low chroma rule.
                if minimum >= 218 && maximum - minimum <= 42 {
                    mask[(y - minimumY) * cropWidth + (x - minimumX)] = 1
                }
            }
        }

        let fullArea = width * height
        let minimumPixels = max(3, Int(Double(fullArea) * 0.0000022))
        let maximumPixels = max(minimumPixels + 1, Int(Double(fullArea) * 0.00013))
        var visited = [UInt8](repeating: 0, count: mask.count)
        var candidateBuckets = Set<Int>()
        var candidateCount = 0

        for index in mask.indices where mask[index] == 1 && visited[index] == 0 {
            var queue = [index]
            var queueIndex = 0
            visited[index] = 1
            var pixelCount = 0
            var minimumComponentX = cropWidth
            var maximumComponentX = 0
            var minimumComponentY = cropHeight
            var maximumComponentY = 0

            while queueIndex < queue.count {
                let current = queue[queueIndex]
                queueIndex += 1
                pixelCount += 1

                let localX = current % cropWidth
                let localY = current / cropWidth
                minimumComponentX = min(minimumComponentX, localX)
                maximumComponentX = max(maximumComponentX, localX)
                minimumComponentY = min(minimumComponentY, localY)
                maximumComponentY = max(maximumComponentY, localY)

                for deltaY in -1...1 {
                    for deltaX in -1...1 where deltaX != 0 || deltaY != 0 {
                        let neighborX = localX + deltaX
                        let neighborY = localY + deltaY
                        guard neighborX >= 0, neighborX < cropWidth,
                              neighborY >= 0, neighborY < cropHeight else { continue }

                        let neighbor = neighborY * cropWidth + neighborX
                        guard mask[neighbor] == 1, visited[neighbor] == 0 else { continue }
                        visited[neighbor] = 1
                        queue.append(neighbor)
                    }
                }
            }

            guard pixelCount >= minimumPixels, pixelCount <= maximumPixels else { continue }

            let componentWidth = maximumComponentX - minimumComponentX + 1
            let componentHeight = maximumComponentY - minimumComponentY + 1
            guard componentWidth >= 2, componentHeight >= 2,
                  Double(componentWidth) <= Double(width) * 0.04,
                  Double(componentHeight) <= Double(height) * 0.025 else { continue }

            let aspectRatio = Double(componentWidth) / Double(componentHeight)
            let fillRatio = Double(pixelCount) / Double(componentWidth * componentHeight)
            guard aspectRatio >= 0.35, aspectRatio <= 2.8,
                  fillRatio >= 0.20, fillRatio <= 0.95 else { continue }

            let centerX = minimumX + (minimumComponentX + maximumComponentX) / 2
            let centerY = minimumY + (minimumComponentY + maximumComponentY) / 2
            let bucketX = min(15, max(0, centerX * 16 / width))
            let bucketY = min(7, max(0, centerY * 8 / height))
            candidateBuckets.insert(bucketY * 16 + bucketX)
            candidateCount += 1
        }

        return ShinySparkleObservation(
            candidateCount: candidateCount,
            candidateBuckets: candidateBuckets.sorted(),
            validLayout: true
        )
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
