import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

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

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(label: "de.schroeder.PokeAssist.screen-samples", qos: .userInitiated)
    private let liveActivityController = LiveActivityController()
    private let frameAnalyzer = VisionFrameAnalyzer()

    private var stream: SCStream?
    private var totalFrameCount = 0
    private var pendingRecognitionIdentity: RecognitionIdentity?
    private var consecutiveRecognitionMatches = 0

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
                recognitionSummary: self.latestRecognition?.summary ?? "Waiting for Pokémon GO"
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
            pendingRecognitionIdentity = nil
            consecutiveRecognitionMatches = 0
            liveActivityStatus = await liveActivityController.start(
                frameCount: 0,
                status: "Capturing",
                recognitionSummary: "Scanning Pokémon GO"
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
                recognitionSummary: latestRecognition?.summary ?? "Capture failed"
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

        // Updating the UI and Live Activity less often keeps the prototype lightweight.
        guard totalFrameCount == 1 || totalFrameCount.isMultiple(of: 10) else { return }

        frameCount = totalFrameCount

        if totalFrameCount == 1 || totalFrameCount.isMultiple(of: 30) {
            liveActivityController.update(
                frameCount: totalFrameCount,
                status: "Capturing",
                recognitionSummary: latestRecognition?.summary ?? "Scanning Pokémon GO"
            )
        }
    }

    private func applyRecognition(_ recognition: PokemonRecognition) {
        guard recognition.screen != .pokeAssist else {
            pendingRecognitionIdentity = nil
            consecutiveRecognitionMatches = 0
            return
        }

        if !recognition.isPokemonResult, latestRecognition?.isPokemonResult == true {
            pendingRecognitionIdentity = nil
            consecutiveRecognitionMatches = 0
            return
        }

        if recognition.isPokemonResult {
            let identity = RecognitionIdentity(
                pokemonName: recognition.pokemonName,
                combatPower: recognition.combatPower
            )

            if identity == pendingRecognitionIdentity {
                consecutiveRecognitionMatches += 1
            } else {
                pendingRecognitionIdentity = identity
                consecutiveRecognitionMatches = 1

                // Do not leave the previous Pokémon in the Dynamic Island
                // while a newly observed identity is being verified.
                liveActivityController.update(
                    frameCount: frameCount,
                    status: "Capturing",
                    recognitionSummary: "Identifying current Pokémon…"
                )
            }

            // Require the same species/CP evidence twice before presenting a
            // protection decision. This trades a short delay for fewer OCR
            // misclassifications while keeping unknown results fail-safe.
            guard consecutiveRecognitionMatches >= 2 else { return }
        }

        guard recognition != latestRecognition else { return }

        latestRecognition = recognition
        liveActivityController.update(
            frameCount: frameCount,
            status: "Capturing",
            recognitionSummary: recognition.summary
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
            recognitionSummary: latestRecognition?.summary ?? status
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
                recognitionSummary: self.latestRecognition?.summary ?? "Selection cancelled"
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

        Task { @MainActor [weak self] in
            self?.receivedFrame(pixelBuffer: pixelBuffer)
        }
    }
}
