import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<PokeAssistAttributes>?
    private var pendingUpdateState: PokeAssistAttributes.ContentState?
    private var updateTask: Task<Void, Never>?

    func start(
        frameCount: Int,
        status: String,
        recognitionSummary: String,
        presentation: PokeAssistActivityPresentation = .scanning
    ) async -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Disabled in iPhone Settings"
        }

        if let activity {
            await updateImmediately(
                activity,
                frameCount: frameCount,
                status: status,
                recognitionSummary: recognitionSummary,
                presentation: presentation
            )
            return activityStatus(activity)
        }

        // Activities can outlive an app update. Never reuse an activity that was
        // created by a build whose widget extension could not render it.
        let orphanedActivities = Activity<PokeAssistAttributes>.activities
        for orphanedActivity in orphanedActivities {
            await orphanedActivity.end(nil, dismissalPolicy: .immediate)
        }

        if !orphanedActivities.isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let attributes = PokeAssistAttributes(sessionName: "Pokemon GO capture")
        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: status,
            recognitionSummary: recognitionSummary,
            presentation: presentation
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            guard let activity else { return "Unavailable" }
            return activityStatus(activity)
        } catch {
            return "Unavailable: \(error.localizedDescription)"
        }
    }

    func update(
        frameCount: Int,
        status: String,
        recognitionSummary: String,
        presentation: PokeAssistActivityPresentation = .scanning
    ) {
        guard let activity else { return }

        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: status,
            recognitionSummary: recognitionSummary,
            presentation: presentation
        )
        pendingUpdateState = state
        guard updateTask == nil else { return }

        updateTask = Task { @MainActor [weak self] in
            await self?.flushPendingUpdates(for: activity)
        }
    }

    private func flushPendingUpdates(for activity: Activity<PokeAssistAttributes>) async {
        while !Task.isCancelled, let state = pendingUpdateState {
            pendingUpdateState = nil
            let content = ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(10),
                relevanceScore: 100
            )
            await activity.update(content)
        }

        updateTask = nil
    }

    private func updateImmediately(
        _ activity: Activity<PokeAssistAttributes>,
        frameCount: Int,
        status: String,
        recognitionSummary: String,
        presentation: PokeAssistActivityPresentation
    ) async {
        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: status,
            recognitionSummary: recognitionSummary,
            presentation: presentation
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(10),
            relevanceScore: 100
        )

        await activity.update(content)
    }

    private func activityStatus(_ activity: Activity<PokeAssistAttributes>) -> String {
        "ActivityKit: \(String(describing: activity.activityState).capitalized)"
    }

    func end(
        frameCount: Int,
        recognitionSummary: String,
        presentation: PokeAssistActivityPresentation = .scanning
    ) {
        guard let activity else { return }
        self.activity = nil
        pendingUpdateState = nil
        updateTask?.cancel()
        updateTask = nil

        let state = PokeAssistAttributes.ContentState(
            frameCount: frameCount,
            status: "Stopped",
            recognitionSummary: recognitionSummary,
            presentation: presentation
        )
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 100)

        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
