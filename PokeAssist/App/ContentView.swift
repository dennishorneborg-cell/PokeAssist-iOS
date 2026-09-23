import SwiftUI

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    statusCard
                    diagnosticsCard
                    recognitionCard
                    controls
                    instructions
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PokeAssist")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("iOS 27 capture test")
                .font(.title2.bold())

            Text("This prototype verifies that full-display capture continues while Pokemon GO is in the foreground.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label(captureManager.status, systemImage: captureManager.isCapturing ? "record.circle.fill" : "pause.circle")
                    .foregroundStyle(captureManager.isCapturing ? .green : .secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text(captureManager.frameCount.formatted())
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("frames")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let errorMessage = captureManager.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Label("Live Activity", systemImage: "wave.3.right.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(captureManager.liveActivityStatus)
                    .font(.caption)
                    .foregroundStyle(captureManager.liveActivityStatus.contains("Active") ? Color.green : Color.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var recognitionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("On-device recognition", systemImage: "text.viewfinder")
                .font(.headline)

            if let recognition = captureManager.latestRecognition {
                Text(recognition.summary(
                    shinyDetected: captureManager.isShinyDetected,
                    eventDetected: captureManager.isEventDetected
                ))
                    .font(.title3.bold())

                if captureManager.isShinyDetected {
                    Label("Species-specific Shiny appearance confirmed (beta)", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.yellow)
                } else if recognition.isPokemonResult {
                    Label("Shiny not confirmed by a calibrated visual rule", systemImage: "questionmark.diamond")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if captureManager.isEventDetected {
                    Label("Visible event costume confirmed (beta)", systemImage: "party.popper.fill")
                        .font(.headline)
                        .foregroundStyle(.purple)
                }

                if recognition.isDynamax {
                    Label("Dynamax detected", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .foregroundStyle(.pink)
                }

                if let sizeClass = recognition.sizeClass {
                    Label("Size marker: \(sizeClass.rawValue)", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                }

                Text("Vision confidence: \(recognition.confidence, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if recognition.isPokemonResult {
                    Divider()

                    Label(recognition.protection.headline, systemImage: recognition.protection.symbolName)
                        .font(.headline)
                        .foregroundStyle(
                            recognition.protection.transferAdvice == .doNotTransfer
                                ? Color.red
                                : Color.orange
                        )

                    ForEach(
                        recognition.protection.detailLines(eventDetected: captureManager.isEventDetected),
                        id: \.self
                    ) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("No visual match is not proof that a Pokémon is normal. PokeAssist never marks a Pokémon as safe to transfer.")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                if let values = recognition.individualValues {
                    Text("Experimental IV: Attack \(values.attack) · Defense \(values.defense) · HP \(values.stamina) · \(values.percentage)%")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)

                    if values.isPVPCandidate {
                        Label("PvP IV pattern (beta; not a ranking guarantee)", systemImage: "shield.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                    }
                }

                if let observedText = recognition.observedText, !recognition.isPokemonResult {
                    Text("Read: \(observedText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                Text(captureManager.isCapturing ? "Scanning Pokémon GO…" : "Starts with screen capture")
                    .foregroundStyle(.secondary)
            }

            Text("OCR runs locally on the iPhone. Frames are not saved or uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Capture diagnostics (local)", systemImage: "waveform.path.ecg")
                .font(.headline)

            diagnosticRow("Capture time", value: captureManager.diagnostics.elapsed)
            diagnosticRow(
                "Thermal state",
                value: captureManager.diagnostics.thermalState,
                tint: captureManager.diagnostics.thermalState == "Critical"
                    ? .red
                    : (captureManager.diagnostics.thermalState == "Hot" ? .orange : .primary)
            )
            diagnosticRow(
                "App memory",
                value: captureManager.diagnostics.memoryMB == 0
                    ? "—"
                    : "\(captureManager.diagnostics.memoryMB) MB"
            )
            diagnosticRow(
                "Capture / processed",
                value: String(
                    format: "%.1f / %.1f fps",
                    captureManager.diagnostics.captureFramesPerSecond,
                    captureManager.diagnostics.processedPerSecond
                )
            )
            diagnosticRow(
                "ScreenCaptureKit callbacks",
                value: String(format: "%.1f fps", captureManager.diagnostics.captureCallbacksPerSecond)
            )
            diagnosticRow(
                "Largest frame gap",
                value: String(format: "%.0f ms", captureManager.diagnostics.maximumCaptureGapMilliseconds)
            )
            diagnosticRow(
                "Invalid buffers / timestamp issues",
                value: "\(captureManager.diagnostics.invalidCaptureBuffers) / \(captureManager.diagnostics.captureTimestampIssues)"
            )
            diagnosticRow(
                "Frames gated",
                value: "\(captureManager.diagnostics.droppedPercent)%"
            )
            diagnosticRow(
                "Vision avg / last",
                value: String(
                    format: "%.0f / %.0f ms",
                    captureManager.diagnostics.visionAverageMilliseconds,
                    captureManager.diagnostics.visionLastMilliseconds
                )
            )
            diagnosticRow(
                "Vision skipped",
                value: captureManager.diagnostics.visionSkipped.formatted()
            )
            diagnosticRow(
                "Appearance avg / last",
                value: String(
                    format: "%.0f / %.0f ms",
                    captureManager.diagnostics.appearanceAverageMilliseconds,
                    captureManager.diagnostics.appearanceLastMilliseconds
                )
            )
            diagnosticRow(
                "Appearance skipped",
                value: captureManager.diagnostics.appearanceSkipped.formatted()
            )
            diagnosticRow(
                "Last Pokémon confirmation",
                value: captureManager.diagnostics.lastRecognitionConfirmationMilliseconds.map {
                    String(format: "%.0f ms", $0)
                } ?? "—"
            )
            diagnosticRow(
                "Pending candidate age",
                value: captureManager.diagnostics.pendingRecognitionMilliseconds.map {
                    String(format: "%.1f s", $0 / 1000)
                } ?? "—"
            )
            diagnosticRow(
                "Candidate restarts",
                value: captureManager.diagnostics.recognitionCandidateRestarts.formatted()
            )

            Text("Sampled every 10 seconds. Measurements stay on this iPhone; no frames or diagnostics are uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func diagnosticRow(_ title: String, value: String, tint: Color = .secondary) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .font(.subheadline)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                captureManager.presentCapturePicker()
            } label: {
                Label("Start screen capture", systemImage: "rectangle.inset.filled.and.person.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(captureManager.isCapturing || captureManager.isPreparing)

            Button(role: .destructive) {
                Task {
                    await captureManager.stopCapture()
                }
            } label: {
                Label("Stop capture", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!captureManager.isCapturing)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How to test", systemImage: "checklist")
                .font(.headline)

            Text("1. Start capture and approve the full display in Apple's picker.")
            Text("2. Wait until the frame counter increases.")
            Text("3. Open Pokemon GO, then open a Pokémon detail or appraisal screen.")
            Text("4. Watch the Dynamic Island and return here to verify the recognition result.")
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    ContentView()
}
