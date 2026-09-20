import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class CaptureManager: NSObject, ObservableObject {
    @Published private(set) var frameCount = 0
    @Published private(set) var isCapturing = false
    @Published private(set) var isPreparing = false
    @Published private(set) var status = "Ready"
    @Published private(set) var errorMessage: String?

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(label: "de.schroeder.PokeAssist.screen-samples", qos: .userInitiated)
    private let liveActivityController = LiveActivityController()

    private var stream: SCStream?
    private var totalFrameCount = 0

    func presentCapturePicker() {
        guard !isCapturing, !isPreparing else { return }

        errorMessage = nil
        status = "Waiting for display selection"
        isPreparing = true

        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false

        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    func stopCapture() async {
        guard let activeStream = stream else {
            resetStoppedState()
            return
        }

        do {
            try await activeStream.stopCapture()
        } catch {
            errorMessage = "Capture stopped with an error: \(error.localizedDescription)"
        }

        try? activeStream.removeStreamOutput(self, type: .screen)
        stream = nil
        picker.remove(self)
        picker.isActive = false
        liveActivityController.end(frameCount: frameCount)
        resetStoppedState()
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
            liveActivityController.start(frameCount: 0)
        } catch {
            stream = nil
            isCapturing = false
            isPreparing = false
            status = "Capture failed"
            errorMessage = error.localizedDescription
            picker.remove(self)
            picker.isActive = false
        }
    }

    private func receivedFrame() {
        totalFrameCount += 1

        // Updating the UI and Live Activity less often keeps the prototype lightweight.
        guard totalFrameCount == 1 || totalFrameCount.isMultiple(of: 10) else { return }

        frameCount = totalFrameCount

        if totalFrameCount == 1 || totalFrameCount.isMultiple(of: 30) {
            liveActivityController.update(frameCount: totalFrameCount, status: "Capturing")
        }
    }

    private func resetStoppedState() {
        isCapturing = false
        isPreparing = false
        status = "Stopped"
    }

    private func captureFailed(_ error: any Error) {
        stream = nil
        isCapturing = false
        isPreparing = false
        status = "Capture failed"
        errorMessage = error.localizedDescription
        liveActivityController.end(frameCount: frameCount)
        picker.remove(self)
        picker.isActive = false
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
            self?.captureFailed(error)
        }
    }
}

extension CaptureManager: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        Task { @MainActor [weak self] in
            self?.receivedFrame()
        }
    }
}
