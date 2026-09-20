import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<PokeAssistAttributes>?

    func start(frameCount: Int, status: String, recognitionSummary: String) -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Disabled in iPhone Settings"
        }

        if activity == nil {
            activity = Activity<PokeAssistAttributes>.activities.first
        }

        if activity != nil {
            update(
                frameCount: frameCount,
                status: status,
                recognitionSummary: recognitionSummary
            )
            return "Running"
        }

        let attributes = PokeAssistAttributes(sessionName: "Pokemon GO capture")
        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: status,
            recognitionSummary: recognitionSummary
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            return "Running"
        } catch {
            return "Unavailable: \(error.localizedDescription)"
        }
    }

    func update(frameCount: Int, status: String, recognitionSummary: String) {
        guard let activity else { return }

        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: status,
            recognitionSummary: recognitionSummary
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(10),
            relevanceScore: 100
        )

        Task {
            await activity.update(content)
        }
    }

    func end(frameCount: Int, recognitionSummary: String) {
        guard let activity else { return }
        self.activity = nil

        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: "Stopped",
            recognitionSummary: recognitionSummary
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
