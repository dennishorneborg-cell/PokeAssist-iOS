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
                    Text(context.state.recognitionSummary)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("PA")
                        .font(.headline.bold())
                        .foregroundStyle(.green)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("PokeAssist")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.frameCount.formatted())
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.recognitionSummary)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            } compactLeading: {
                Text("PA")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.frameCount.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            } minimal: {
                Text("P")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }
}
