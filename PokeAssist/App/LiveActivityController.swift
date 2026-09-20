import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<PokeAssistAttributes>?

    func start(frameCount: Int) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = PokeAssistAttributes(sessionName: "Pokemon GO capture")
        let state = PokeAssistAttributes.ContentState(frameCount: frameCount, status: "Starting")
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            // Capture remains useful even when Live Activities are disabled or unavailable.
        }
    }

    func update(frameCount: Int, status: String) {
        guard let activity else { return }

        let state = PokeAssistAttributes.ContentState(frameCount: frameCount, status: status)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))

        Task {
            await activity.update(content)
        }
    }

    func end(frameCount: Int) {
        guard let activity else { return }
        self.activity = nil

        let state = PokeAssistAttributes.ContentState(frameCount: frameCount, status: "Stopped")
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
