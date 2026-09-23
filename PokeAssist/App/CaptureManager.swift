import CoreMedia
import CoreVideo
import Darwin
import Foundation
import ScreenCaptureKit

private final class FrameDeliveryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isFramePending = false
    private var lastAcceptedTime: TimeInterval = 0
    private var callbackCount = 0
    private var validFrameCount = 0
    private var invalidSampleCount = 0
    private var notReadySampleCount = 0
    private var missingImageBufferCount = 0
    private var droppedCount = 0
    private var timestampIssueCount = 0
    private var lastPresentationTime: Double?
    private var maximumPresentationGapMilliseconds = 0.0

    func recordScreenCallback() {
        lock.lock()
        callbackCount += 1
        lock.unlock()
    }

    func recordInvalidSample() {
        lock.lock()
        invalidSampleCount += 1
        lock.unlock()
    }

    func recordNotReadySample() {
        lock.lock()
        notReadySampleCount += 1
        lock.unlock()
    }

    func recordMissingImageBuffer() {
        lock.lock()
        missingImageBufferCount += 1
        lock.unlock()
    }

    func begin(presentationTime: CMTime) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        validFrameCount += 1
        let presentationSeconds = CMTimeGetSeconds(presentationTime)
        if presentationSeconds.isFinite, presentationSeconds >= 0 {
            if let lastPresentationTime {
                let gap = presentationSeconds - lastPresentationTime
                if gap > 0 {
                    maximumPresentationGapMilliseconds = max(
                        maximumPresentationGapMilliseconds,
                        gap * 1000
                    )
                } else {
                    timestampIssueCount += 1
                }
            }
            lastPresentationTime = presentationSeconds
        } else {
            timestampIssueCount += 1
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard !isFramePending, now - lastAcceptedTime >= 1.0 / 4.0 else {
            droppedCount += 1
            return false
        }
        isFramePending = true
        lastAcceptedTime = now
        return true
    }

    func end() {
        lock.lock()
        isFramePending = false
        lock.unlock()
    }

    func reset() {
        lock.lock()
        isFramePending = false
        lastAcceptedTime = 0
        callbackCount = 0
        validFrameCount = 0
        invalidSampleCount = 0
        notReadySampleCount = 0
        missingImageBufferCount = 0
        droppedCount = 0
        timestampIssueCount = 0
        lastPresentationTime = nil
        maximumPresentationGapMilliseconds = 0
        lock.unlock()
    }

    func snapshot() -> (
        callbacks: Int,
        validFrames: Int,
        invalidSamples: Int,
        notReadySamples: Int,
        missingImageBuffers: Int,
        dropped: Int,
        timestampIssues: Int,
        maximumGapMilliseconds: Double
    ) {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = (
            callbackCount,
            validFrameCount,
            invalidSampleCount,
            notReadySampleCount,
            missingImageBufferCount,
            droppedCount,
            timestampIssueCount,
            maximumPresentationGapMilliseconds
        )
        maximumPresentationGapMilliseconds = 0
        return snapshot
    }
}

struct CaptureDiagnostics {
    var elapsed = "—"
    var thermalState = "—"
    var memoryMB = 0
    var captureCallbacksPerSecond = 0.0
    var captureFramesPerSecond = 0.0
    var processedPerSecond = 0.0
    var droppedPercent = 0
    var invalidCaptureBuffers = 0
    var maximumCaptureGapMilliseconds = 0.0
    var captureTimestampIssues = 0
    var visionAverageMilliseconds = 0.0
    var visionLastMilliseconds = 0.0
    var visionSkipped = 0
    var appearanceAverageMilliseconds = 0.0
    var appearanceLastMilliseconds = 0.0
    var appearanceSkipped = 0
    var lastRecognitionConfirmationMilliseconds: Double?
    var pendingRecognitionMilliseconds: Double?
    var recognitionCandidateRestarts = 0
    var liveActivityQueueMilliseconds = 0.0
    var liveActivityLastRequestMilliseconds = 0.0
    var liveActivityAverageRequestMilliseconds = 0.0
}

@MainActor
final class CaptureManager: NSObject, ObservableObject {
    private struct RecognitionIdentity: Equatable {
        let pokemonName: String?
        let combatPower: Int?
    }

    @Published private(set) var frameCount = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isPreparing = false
    @Published private(set) var status = "Ready"
    @Published private(set) var errorMessage: String?
    @Published private(set) var liveActivityStatus = "Not started"
    @Published private(set) var latestRecognition: PokemonRecognition?
    @Published private(set) var isShinyDetected = false
    @Published private(set) var isEventDetected = false
    @Published private(set) var diagnostics = CaptureDiagnostics()

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(label: "de.schroeder.PokeAssist.screen-samples", qos: .userInitiated)
    private let liveActivityController = LiveActivityController()
    private let frameAnalyzer = VisionFrameAnalyzer()
    private let appearanceAnalyzer = PokemonAppearanceAnalyzer()
    nonisolated private let frameDeliveryGate = FrameDeliveryGate()

    private var stream: SCStream?
    private var totalFrameCount = 0
    private var captureStartedAt: TimeInterval?
    private var diagnosticsTask: Task<Void, Never>?
    private var lastDiagnosticSample: (
        time: TimeInterval,
        callbacks: Int,
        validFrames: Int,
        processed: Int
    )?
    private var pendingRecognitionIdentity: RecognitionIdentity?
    private var pendingRecognitionStartedAt: TimeInterval?
    private var lastRecognitionConfirmationMilliseconds: Double?
    private var recognitionCandidateRestarts = 0
    private var consecutiveRecognitionMatches = 0
    private var consecutiveNonPokemonResults = 0
    private var combatPowerIsCached = false
    private var currentObservedScreen: PokemonRecognition.Screen = .unknown
    private var shinyPositiveStreak = 0
    private var shinyNegativeStreak = 0
    private var eventPositiveStreak = 0
    private var eventNegativeStreak = 0
    private var lastCombatPowerBySpecies: [String: Int] = [:]

    func presentCapturePicker() {
        guard !isCapturing, !isPreparing else { return }

        errorMessage = nil
        status = "Waiting for display selection"
        isPreparing = true

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.liveActivityStatus = await self.liveActivityController.start(
                frameCount: self.frameCount,
                status: "Select full display",
                recognitionSummary: self.currentRecognitionSummary(fallback: "Waiting for Pokémon GO"),
                presentation: self.currentActivityPresentation
            )

            var configuration = SCContentSharingPickerConfiguration()
            configuration.showsMicrophoneControl = false
            configuration.showsCameraControl = false

            self.picker.defaultConfiguration = configuration
            self.picker.add(self)
            self.picker.isActive = true
            self.picker.present()
        }
    }

    func stopCapture() async {
        guard let activeStream = stream else {
            resetStoppedState()
            return
        }

        do {
            try await activeStream.stopCapture()
        } catch {
            if !isUserStoppedError(error) {
                errorMessage = "Capture stopped with an error: \(error.localizedDescription)"
            }
        }

        finishCapture(status: "Stopped", errorMessage: nil)
    }

    private func startCapture(with filter: SCContentFilter) async {
        isPreparing = true
        errorMessage = nil
        status = "Starting capture"

        if let activeStream = stream {
            try? await activeStream.stopCapture()
            try? activeStream.removeStreamOutput(self, type: .screen)
        }

        let configuration = SCStreamConfiguration()

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)

        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await newStream.startCapture()

            stream = newStream
            totalFrameCount = 0
            frameCount = 0
            captureStartedAt = ProcessInfo.processInfo.systemUptime
            frameDeliveryGate.reset()
            frameAnalyzer.resetMetrics()
            appearanceAnalyzer.resetMetrics()
            liveActivityController.resetMetrics()
            lastDiagnosticSample = nil
            diagnostics = CaptureDiagnostics()
            isCapturing = true
            isPreparing = false
            status = "Capturing full display"
            latestRecognition = nil
            isShinyDetected = false
            isEventDetected = false
            pendingRecognitionIdentity = nil
            pendingRecognitionStartedAt = nil
            lastRecognitionConfirmationMilliseconds = nil
            recognitionCandidateRestarts = 0
            consecutiveRecognitionMatches = 0
            consecutiveNonPokemonResults = 0
            combatPowerIsCached = false
            currentObservedScreen = .unknown
            shinyPositiveStreak = 0
            shinyNegativeStreak = 0
            eventPositiveStreak = 0
            eventNegativeStreak = 0
            lastCombatPowerBySpecies.removeAll(keepingCapacity: true)
            liveActivityStatus = await liveActivityController.start(
                frameCount: 0,
                status: "Capturing",
                recognitionSummary: "Scanning Pokémon GO",
                presentation: .scanning
            )
            startDiagnosticsSampling()
            refreshDiagnostics()
        } catch {
            stream = nil
            isCapturing = false
            isPreparing = false
            status = "Capture failed"
            errorMessage = error.localizedDescription
            picker.remove(self)
            picker.isActive = false
            liveActivityController.end(
                frameCount: frameCount,
                recognitionSummary: currentRecognitionSummary(fallback: "Capture failed"),
                presentation: currentActivityPresentation
            )
        }
    }

    private func receivedFrame(pixelBuffer: CVPixelBuffer) {
        totalFrameCount += 1

        frameAnalyzer.submit(pixelBuffer: pixelBuffer) { [weak self] recognition in
            Task { @MainActor [weak self] in
                self?.applyRecognition(recognition)
            }
        }

        if (currentObservedScreen == .pokemonDetails || currentObservedScreen == .appraisal),
           consecutiveRecognitionMatches >= 2,
           let pokemonName = latestRecognition?.pokemonName {
            appearanceAnalyzer.submit(pixelBuffer: pixelBuffer, pokemonName: pokemonName) { [weak self] observation in
                Task { @MainActor [weak self] in
                    self?.applyAppearanceObservation(observation)
                }
            }
        }

        // Update the in-app frame counter periodically, but keep frame-only
        // changes out of ActivityKit. Frequent Live Activity updates can be
        // coalesced or delayed by the system and carry no Pokémon information.
        guard totalFrameCount == 1 || totalFrameCount.isMultiple(of: 10) else { return }

        frameCount = totalFrameCount
    }

    private func startDiagnosticsSampling() {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self, self.isCapturing else { return }
                self.refreshDiagnostics()
            }
        }
    }

    private func refreshDiagnostics() {
        let now = ProcessInfo.processInfo.systemUptime
        let capture = frameDeliveryGate.snapshot()
        let uptime = captureStartedAt.map { max(0, now - $0) } ?? 0
        let elapsedSeconds = Int(uptime)
        let elapsed = String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unknown"
        }

        let previous = lastDiagnosticSample
        let interval = previous.map { max(0.001, now - $0.time) } ?? 0
        let captureCallbacksPerSecond = previous.map {
            Double(capture.callbacks - $0.callbacks) / interval
        } ?? 0
        let captureFramesPerSecond = previous.map {
            Double(capture.validFrames - $0.validFrames) / interval
        } ?? 0
        let processedPerSecond = previous.map { Double(totalFrameCount - $0.processed) / interval } ?? 0
        let droppedPercent = capture.validFrames > 0
            ? capture.dropped * 100 / capture.validFrames
            : 0
        let invalidCaptureBuffers = capture.invalidSamples
            + capture.notReadySamples
            + capture.missingImageBuffers
        let analysis = frameAnalyzer.metricsSnapshot()
        let appearance = appearanceAnalyzer.metricsSnapshot()
        let liveActivity = liveActivityController.metricsSnapshot()
        let pendingRecognitionMilliseconds = pendingRecognitionStartedAt.map {
            max(0, now - $0) * 1000
        }

        diagnostics = CaptureDiagnostics(
            elapsed: elapsed,
            thermalState: thermal,
            memoryMB: Self.currentMemoryFootprintMB(),
            captureCallbacksPerSecond: captureCallbacksPerSecond,
            captureFramesPerSecond: captureFramesPerSecond,
            processedPerSecond: processedPerSecond,
            droppedPercent: droppedPercent,
            invalidCaptureBuffers: invalidCaptureBuffers,
            maximumCaptureGapMilliseconds: capture.maximumGapMilliseconds,
            captureTimestampIssues: capture.timestampIssues,
            visionAverageMilliseconds: analysis.averageMilliseconds,
            visionLastMilliseconds: analysis.lastMilliseconds,
            visionSkipped: analysis.skipped,
            appearanceAverageMilliseconds: appearance.averageMilliseconds,
            appearanceLastMilliseconds: appearance.lastMilliseconds,
            appearanceSkipped: appearance.skipped,
            lastRecognitionConfirmationMilliseconds: lastRecognitionConfirmationMilliseconds,
            pendingRecognitionMilliseconds: pendingRecognitionMilliseconds,
            recognitionCandidateRestarts: recognitionCandidateRestarts,
            liveActivityQueueMilliseconds: liveActivity.lastQueueMilliseconds,
            liveActivityLastRequestMilliseconds: liveActivity.lastRequestMilliseconds,
            liveActivityAverageRequestMilliseconds: liveActivity.averageRequestMilliseconds
        )
        lastDiagnosticSample = (now, capture.callbacks, capture.validFrames, totalFrameCount)
    }

    private static func currentMemoryFootprintMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / 1_048_576)
    }

    private func applyRecognition(_ freshRecognition: PokemonRecognition) {
        let (recognition, cachedCombatPower) = preservingCoveredCombatPower(in: freshRecognition)
        if recognition.screen != .pokeAssist, recognition.screen != .unknown {
            currentObservedScreen = recognition.screen
        }

        guard recognition.screen != .pokeAssist else {
            pendingRecognitionIdentity = nil
            pendingRecognitionStartedAt = nil
            consecutiveRecognitionMatches = 0
            consecutiveNonPokemonResults = 0
            combatPowerIsCached = false
            return
        }

        if !recognition.isPokemonResult, latestRecognition?.isPokemonResult == true {
            consecutiveNonPokemonResults += 1

            // Vision can miss one or two frames during Pokémon animations.
            // Preserve confirmed traits through those brief gaps so the
            // Dynamic Island does not alternate between green and its badges.
            guard consecutiveNonPokemonResults >= 4 else { return }

            pendingRecognitionIdentity = nil
            pendingRecognitionStartedAt = nil
            consecutiveRecognitionMatches = 0
            consecutiveNonPokemonResults = 0
            resetAppearanceEvidence()
            latestRecognition = recognition
            liveActivityController.update(
                frameCount: frameCount,
                status: "Capturing",
                recognitionSummary: "Scanning Pokémon GO",
                presentation: .scanning
            )
            return
        }

        if recognition.isPokemonResult {
            consecutiveNonPokemonResults = 0
            let identity = RecognitionIdentity(
                pokemonName: recognition.pokemonName,
                combatPower: recognition.combatPower
            )

            if identity == pendingRecognitionIdentity {
                consecutiveRecognitionMatches += 1
            } else {
                if pendingRecognitionStartedAt != nil {
                    recognitionCandidateRestarts += 1
                }
                pendingRecognitionIdentity = identity
                consecutiveRecognitionMatches = 1
                pendingRecognitionStartedAt = ProcessInfo.processInfo.systemUptime
            }

            // Require the same species/CP evidence twice before presenting a
            // protection decision. Keep the last confirmed state during the
            // first sample so one OCR typo cannot flash a green-only badge.
            guard consecutiveRecognitionMatches >= 2 else { return }

            let previousIdentity = latestRecognition.map {
                RecognitionIdentity(pokemonName: $0.pokemonName, combatPower: $0.combatPower)
            }
            if identity != previousIdentity,
               let startedAt = pendingRecognitionStartedAt {
                lastRecognitionConfirmationMilliseconds =
                    (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
            }
            pendingRecognitionStartedAt = nil
            if identity != previousIdentity {
                resetAppearanceEvidence()
            }
        }

        guard recognition != latestRecognition || cachedCombatPower != combatPowerIsCached else { return }

        latestRecognition = recognition
        combatPowerIsCached = cachedCombatPower
        liveActivityController.update(
            frameCount: frameCount,
            status: "Capturing",
            recognitionSummary: recognition.summary(
                shinyDetected: isShinyDetected,
                eventDetected: isEventDetected
            ),
            presentation: activityPresentation(for: recognition)
        )
    }

    private func preservingCoveredCombatPower(
        in recognition: PokemonRecognition
    ) -> (PokemonRecognition, Bool) {
        // The expanded Island can cover Pokémon GO's CP label on either
        // Pokémon screen. Keep the last value by species for this capture
        // session; always label a reused value as cached because a second
        // individual of the same species can have different CP.
        guard recognition.isPokemonResult,
              let name = recognition.pokemonName else {
            return (recognition, false)
        }

        if let combatPower = recognition.combatPower {
            lastCombatPowerBySpecies[name] = combatPower
            return (recognition, false)
        }

        guard let combatPower = lastCombatPowerBySpecies[name] else {
            return (recognition, false)
        }

        return (PokemonRecognition(
            screen: recognition.screen,
            pokemonName: recognition.pokemonName,
            combatPower: combatPower,
            confidence: recognition.confidence,
            observedText: recognition.observedText,
            individualValues: recognition.individualValues,
            protection: recognition.protection,
            sizeClass: recognition.sizeClass,
            isDynamax: recognition.isDynamax
        ), true)
    }

    private func applyAppearanceObservation(_ observation: PokemonAppearanceObservation) {
        guard currentObservedScreen == .pokemonDetails || currentObservedScreen == .appraisal,
              let recognition = latestRecognition,
              recognition.isPokemonResult,
              consecutiveRecognitionMatches >= 2,
              observation.pokemonName == recognition.pokemonName else { return }

        // Confirm after two matching samples, but also clear a confirmed trait
        // after two contrary samples. Sticky OR logic would otherwise carry a
        // Shiny/event result over to another individual of the same species.
        shinyPositiveStreak = observation.shinyDetected ? shinyPositiveStreak + 1 : 0
        shinyNegativeStreak = observation.shinyDetected ? 0 : shinyNegativeStreak + 1
        eventPositiveStreak = observation.eventDetected ? eventPositiveStreak + 1 : 0
        eventNegativeStreak = observation.eventDetected ? 0 : eventNegativeStreak + 1

        let shinyConfirmed = shinyPositiveStreak >= 2
            ? true
            : (shinyNegativeStreak >= 2 ? false : isShinyDetected)
        let eventConfirmed = eventPositiveStreak >= 2
            ? true
            : (eventNegativeStreak >= 2 ? false : isEventDetected)
        guard shinyConfirmed != isShinyDetected || eventConfirmed != isEventDetected else { return }

        isShinyDetected = shinyConfirmed
        isEventDetected = eventConfirmed
        liveActivityController.update(
            frameCount: frameCount,
            status: "Capturing",
            recognitionSummary: recognition.summary(
                shinyDetected: isShinyDetected,
                eventDetected: isEventDetected
            ),
            presentation: activityPresentation(for: recognition)
        )
    }

    private func resetAppearanceEvidence() {
        shinyPositiveStreak = 0
        shinyNegativeStreak = 0
        eventPositiveStreak = 0
        eventNegativeStreak = 0
        isShinyDetected = false
        isEventDetected = false
    }

    private func currentRecognitionSummary(fallback: String) -> String {
        latestRecognition?.summary(
            shinyDetected: isShinyDetected,
            eventDetected: isEventDetected
        ) ?? fallback
    }

    private var currentActivityPresentation: PokeAssistActivityPresentation {
        guard let latestRecognition else { return .scanning }
        return activityPresentation(for: latestRecognition)
    }

    private func activityPresentation(for recognition: PokemonRecognition) -> PokeAssistActivityPresentation {
        let mode: PokeAssistActivityMode
        switch recognition.screen {
        case .pokemonDetails: mode = .pokemon
        case .appraisal: mode = .appraisal
        case .map, .pokeAssist, .unknown: mode = .scanning
        }

        let rarity: PokeAssistActivityRarity
        switch recognition.protection.rarity {
        case .standard: rarity = .standard
        case .legendary: rarity = .legendary
        case .mythical: rarity = .mythical
        case .ultraBeast: rarity = .ultraBeast
        case .unknown: rarity = .unknown
        }

        let size: PokeAssistActivitySize
        switch recognition.sizeClass {
        case .xxs: size = .xxs
        case .xxl: size = .xxl
        case nil: size = .none
        }

        return PokeAssistActivityPresentation(
            mode: mode,
            pokemonName: recognition.pokemonName,
            combatPower: recognition.combatPower,
            combatPowerIsCached: combatPowerIsCached,
            ivAttack: recognition.individualValues?.attack,
            ivDefense: recognition.individualValues?.defense,
            ivStamina: recognition.individualValues?.stamina,
            ivPercentage: recognition.individualValues?.percentage,
            shinyDetected: isShinyDetected,
            eventDetected: isEventDetected,
            rarity: rarity,
            size: size,
            dynamaxDetected: recognition.isDynamax,
            pvpCandidate: recognition.individualValues?.isPVPCandidate == true
        )
    }

    private func resetStoppedState() {
        isCapturing = false
        isPreparing = false
        status = "Stopped"
    }

    private func captureFailed(_ error: any Error) {
        if isUserStoppedError(error) {
            finishCapture(status: "Stopped", errorMessage: nil)
            return
        }

        finishCapture(status: "Capture failed", errorMessage: error.localizedDescription)
    }

    private func finishCapture(status: String, errorMessage: String?) {
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        refreshDiagnostics()
        captureStartedAt = nil
        if let activeStream = stream {
            try? activeStream.removeStreamOutput(self, type: .screen)
        }

        stream = nil
        isCapturing = false
        isPreparing = false
        self.status = status
        self.errorMessage = errorMessage
        liveActivityController.end(
            frameCount: frameCount,
            recognitionSummary: currentRecognitionSummary(fallback: status),
            presentation: currentActivityPresentation
        )
        picker.remove(self)
        picker.isActive = false
    }

    private func isUserStoppedError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamError.errorDomain
            && nsError.code == SCStreamError.Code.userStopped.rawValue
    }
}

extension CaptureManager: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            await self?.startCapture(with: filter)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPreparing = false
            self.status = "Selection cancelled"
            self.liveActivityController.end(
                frameCount: self.frameCount,
                recognitionSummary: self.currentRecognitionSummary(fallback: "Selection cancelled"),
                presentation: self.currentActivityPresentation
            )
            self.picker.remove(self)
            self.picker.isActive = false
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in
            self?.captureFailed(error)
        }
    }
}

extension CaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.captureFailed(error)
        }
    }
}

extension CaptureManager: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        let deliveryGate = frameDeliveryGate
        deliveryGate.recordScreenCallback()

        guard sampleBuffer.isValid else {
            deliveryGate.recordInvalidSample()
            return
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            deliveryGate.recordNotReadySample()
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            deliveryGate.recordMissingImageBuffer()
            return
        }

        // ScreenCaptureKit's iOS configuration doesn't expose a frame-rate
        // limit. Process at most 4 fresh frames per second and drop the rest
        // before they can enqueue MainActor work or analysis. We still count
        // every callback and sample timestamp to diagnose source-side stalls.
        guard deliveryGate.begin(
            presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        ) else { return }

        Task { @MainActor [weak self] in
            defer { deliveryGate.end() }
            self?.receivedFrame(pixelBuffer: pixelBuffer)
        }
    }
}
