import ActivityKit
import SwiftUI
import WidgetKit

struct PokeAssistLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PokeAssistAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.sessionName)
                        .font(.headline)
                    Text("\(context.state.frameCount.formatted()) frames · \(context.state.status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "viewfinder.circle.fill")
                        .foregroundStyle(.green)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("PokeAssist")
                        .font(.headline)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.frameCount.formatted())
                        .font(.headline.monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text("Capture is running · open Pokemon GO")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "viewfinder.circle.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.frameCount.formatted())
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "viewfinder.circle.fill")
                    .foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }
}
