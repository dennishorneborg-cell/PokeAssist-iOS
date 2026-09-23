import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

private final class FrameDeliveryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isFramePending = false
    private var lastAcceptedTime: TimeInterval = 0

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        guard !isFramePending, now - lastAcceptedTime >= 1.0 / 4.0 else { return false }
        isFramePending = true
        lastAcceptedTime = now
        return true
    }

    func end() {
        lock.lock()
        isFramePending = false
        lock.unlock()
    }
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

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(label: "de.schroeder.PokeAssist.screen-samples", qos: .userInitiated)
    private let liveActivityController = LiveActivityController()
    private let frameAnalyzer = VisionFrameAnalyzer()
    private let appearanceAnalyzer = PokemonAppearanceAnalyzer()
    nonisolated private let frameDeliveryGate = FrameDeliveryGate()

    private var stream: SCStream?
    private var totalFrameCount = 0
    private var pendingRecognitionIdentity: RecognitionIdentity?
    private var consecutiveRecognitionMatches = 0
    private var consecutiveNonPokemonResults = 0
    private var combatPowerIsCached = false
    private var currentObservedScreen: PokemonRecognition.Screen = .unknown
    private var appearanceSamples: [PokemonAppearanceObservation] = []

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
            isCapturing = true
            isPreparing = false
            status = "Capturing full display"
            latestRecognition = nil
            isShinyDetected = false
            isEventDetected = false
            pendingRecognitionIdentity = nil
            consecutiveRecognitionMatches = 0
            consecutiveNonPokemonResults = 0
            combatPowerIsCached = false
            currentObservedScreen = .unknown
            appearanceSamples.removeAll(keepingCapacity: true)
            liveActivityStatus = await liveActivityController.start(
                frameCount: 0,
                status: "Capturing",
                recognitionSummary: "Scanning Pokémon GO",
                presentation: .scanning
            )
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

        // Updating the UI and Live Activity less often keeps the prototype lightweight.
        guard totalFrameCount == 1 || totalFrameCount.isMultiple(of: 10) else { return }

        frameCount = totalFrameCount

        if totalFrameCount == 1 || totalFrameCount.isMultiple(of: 10) {
            liveActivityController.update(
                frameCount: totalFrameCount,
                status: "Capturing",
                recognitionSummary: currentRecognitionSummary(fallback: "Scanning Pokémon GO"),
                presentation: currentActivityPresentation
            )
        }
    }

    private func applyRecognition(_ freshRecognition: PokemonRecognition) {
        let (recognition, cachedCombatPower) = preservingCoveredCombatPower(in: freshRecognition)
        if recognition.screen != .pokeAssist, recognition.screen != .unknown {
            currentObservedScreen = recognition.screen
        }

        guard recognition.screen != .pokeAssist else {
            pendingRecognitionIdentity = nil
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
                pendingRecognitionIdentity = identity
                consecutiveRecognitionMatches = 1
            }

            // Require the same species/CP evidence twice before presenting a
            // protection decision. Keep the last confirmed state during the
            // first sample so one OCR typo cannot flash a green-only badge.
            guard consecutiveRecognitionMatches >= 2 else { return }

            let previousIdentity = latestRecognition.map {
                RecognitionIdentity(pokemonName: $0.pokemonName, combatPower: $0.combatPower)
            }
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
        // The expanded Island covers Pokémon GO's CP label. Retain a value
        // previously read for the same species during appraisal, but label it
        // as cached because another individual of that species may be selected.
        guard recognition.screen == .appraisal,
              recognition.combatPower == nil,
              let previous = latestRecognition,
              previous.isPokemonResult,
              let name = recognition.pokemonName,
              name == previous.pokemonName,
              let combatPower = previous.combatPower else {
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

        appearanceSamples.append(observation)
        if appearanceSamples.count > 5 {
            appearanceSamples.removeFirst(appearanceSamples.count - 5)
        }

        // A trait is published only after two separate frames agree. This is
        // fast enough for a compact glance while rejecting a single animation
        // frame or compression artefact.
        let shinyConfirmed = isShinyDetected || appearanceSamples.filter(\.shinyDetected).count >= 2
        let eventConfirmed = isEventDetected || appearanceSamples.filter(\.eventDetected).count >= 2
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
        appearanceSamples.removeAll(keepingCapacity: true)
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
        guard
            type == .screen,
            sampleBuffer.isValid,
            CMSampleBufferDataIsReady(sampleBuffer),
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        // ScreenCaptureKit's iOS configuration doesn't expose a frame-rate
        // limit. Process at most 4 fresh frames per second and drop the rest
        // before they can enqueue MainActor work or analysis.
        let deliveryGate = frameDeliveryGate
        guard deliveryGate.begin() else { return }

        Task { @MainActor [weak self] in
            defer { deliveryGate.end() }
            self?.receivedFrame(pixelBuffer: pixelBuffer)
        }
    }
}
