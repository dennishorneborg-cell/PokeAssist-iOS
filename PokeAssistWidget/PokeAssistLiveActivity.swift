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

                activityBadges(context.state.presentation)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    activityBadges(context.state.presentation)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.presentation.pokemonName ?? "PokeAssist")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(expandedMetric(context.state))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.recognitionSummary)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            } compactLeading: {
                compactBadges(context.state.presentation)
            } compactTrailing: {
                Text(compactMetric(context.state))
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } minimal: {
                minimalBadge(context.state.presentation)
            }
            .keylineTint(.green)
        }
    }

    @ViewBuilder
    private func activityBadges(_ presentation: PokeAssistActivityPresentation) -> some View {
        HStack(spacing: 3) {
            if presentation.shinyDetected {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
            }

            if presentation.eventDetected {
                Image(systemName: "party.popper.fill")
                    .foregroundStyle(.purple)
            }

            if presentation.rarity.isProtected {
                Image(systemName: raritySymbol(presentation.rarity))
                    .foregroundStyle(.orange)
            }

            if presentation.dynamaxDetected {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.pink)
            }

            if presentation.size != .none {
                Text(presentation.size == .xxl ? "XL" : "XS")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            if presentation.pvpCandidate {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
            }

            if !hasSpecialBadge(presentation) {
                Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption.bold())
    }

    @ViewBuilder
    private func compactBadges(_ presentation: PokeAssistActivityPresentation) -> some View {
        HStack(spacing: 1) {
            if presentation.shinyDetected {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
            }
            if presentation.eventDetected {
                Image(systemName: "party.popper.fill")
                    .foregroundStyle(.purple)
            }
            if presentation.rarity.isProtected {
                Image(systemName: raritySymbol(presentation.rarity))
                    .foregroundStyle(.orange)
            }
            if presentation.dynamaxDetected {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundStyle(.pink)
            }
            if presentation.size != .none {
                Text(presentation.size == .xxl ? "XL" : "XS")
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
            }
            if presentation.pvpCandidate {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
            }
            if !hasSpecialBadge(presentation) {
                Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.system(size: 9, weight: .bold))
    }

    @ViewBuilder
    private func minimalBadge(_ presentation: PokeAssistActivityPresentation) -> some View {
        if presentation.shinyDetected {
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
        } else if presentation.eventDetected {
            Image(systemName: "party.popper.fill")
                .foregroundStyle(.purple)
        } else if presentation.rarity.isProtected {
            Image(systemName: raritySymbol(presentation.rarity))
                .foregroundStyle(.orange)
        } else if presentation.dynamaxDetected {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(.pink)
        } else if presentation.size != .none {
            Text(presentation.size == .xxl ? "XL" : "XS")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.cyan)
        } else if presentation.pvpCandidate {
            Image(systemName: "shield.fill")
                .foregroundStyle(.blue)
        } else {
            Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func compactMetric(_ state: PokeAssistAttributes.ContentState) -> String {
        if state.presentation.mode == .appraisal, let percentage = state.presentation.ivPercentage {
            return "\(percentage)%"
        }
        if let combatPower = state.presentation.combatPower {
            return String(combatPower)
        }
        return state.frameCount.formatted()
    }

    private func expandedMetric(_ state: PokeAssistAttributes.ContentState) -> String {
        if state.presentation.mode == .appraisal, let percentage = state.presentation.ivPercentage {
            return "IV \(percentage)%"
        }
        if let combatPower = state.presentation.combatPower {
            return "CP \(combatPower)"
        }
        return state.frameCount.formatted()
    }

    private func raritySymbol(_ rarity: PokeAssistActivityRarity) -> String {
        switch rarity {
        case .legendary: return "crown.fill"
        case .mythical: return "wand.and.stars"
        case .ultraBeast: return "hexagon.fill"
        case .standard, .unknown: return "viewfinder.circle.fill"
        }
    }

    private func hasSpecialBadge(_ presentation: PokeAssistActivityPresentation) -> Bool {
        presentation.shinyDetected
            || presentation.eventDetected
            || presentation.rarity.isProtected
            || presentation.dynamaxDetected
            || presentation.size != .none
            || presentation.pvpCandidate
    }
}
