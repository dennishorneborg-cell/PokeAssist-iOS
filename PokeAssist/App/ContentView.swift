import SwiftUI

struct ContentView: View {
    @StateObject private var captureManager = CaptureManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    statusCard
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
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
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
            Text("3. Open Pokemon GO and watch the Dynamic Island or Live Activity.")
            Text("4. If the counter keeps increasing, background capture works on this device.")
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
