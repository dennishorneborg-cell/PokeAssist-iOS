import SwiftUI

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    statusCard
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
                Text(recognition.summary(shinyDetected: captureManager.isShinyDetected))
                    .font(.title3.bold())

                if captureManager.isShinyDetected {
                    Label("Animated Shiny sparkle detected (beta)", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.yellow)
                } else if recognition.isPokemonResult {
                    Label("Shiny not visually confirmed", systemImage: "questionmark.diamond")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
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

                    ForEach(recognition.protection.detailLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("No sparkle match is not proof that a Pokémon is not Shiny. PokeAssist never marks a Pokémon as safe to transfer.")
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
