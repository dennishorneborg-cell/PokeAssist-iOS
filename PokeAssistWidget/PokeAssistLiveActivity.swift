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
                    VStack(alignment: .trailing, spacing: 2) {
                        if let combatPower = context.state.presentation.combatPower {
                            Text("CP \(combatPower)")
                                .font(.headline.monospacedDigit())
                        } else if context.state.presentation.mode == .scanning {
                            Text(context.state.frameCount.formatted())
                                .font(.headline.monospacedDigit())
                        } else {
                            Text("CP ?")
                                .font(.headline.monospacedDigit())
                        }

                        if context.state.presentation.mode == .appraisal,
                           let percentage = context.state.presentation.ivPercentage {
                            Text("IV \(percentage)%")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.recognitionSummary)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if context.state.presentation.combatPowerIsCached == true {
                            Text("CP zuletzt erkannt – bei Pokémon-Wechsel prüfen")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                minimalBadges(context.state.presentation)
            }
            .keylineTint(.green)
        }
    }

    @ViewBuilder
    private func activityBadges(_ presentation: PokeAssistActivityPresentation) -> some View {
        HStack(spacing: 3) {
            Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                .foregroundStyle(.green)

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
        }
        .font(.caption.bold())
    }

    @ViewBuilder
    private func compactBadges(_ presentation: PokeAssistActivityPresentation) -> some View {
        HStack(spacing: 1) {
            Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                .foregroundStyle(.green)

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
        }
        .font(.system(size: 8, weight: .bold))
    }

    @ViewBuilder
    private func minimalBadges(_ presentation: PokeAssistActivityPresentation) -> some View {
        // ScreenCaptureKit's recording indicator makes iOS choose the minimal
        // Live Activity presentation. It offers one tiny content slot, so all
        // current traits must be encoded in one deliberately dense view.
        HStack(spacing: -1) {
            Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                .foregroundStyle(.green)

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
                Text(presentation.size == .xxl ? "L" : "S")
                    .font(.system(size: 5.5, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
            }
            if presentation.pvpCandidate {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 6.5, weight: .bold))
        .lineLimit(1)
        .accessibilityLabel("PokeAssist status and detected traits")
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

    private func raritySymbol(_ rarity: PokeAssistActivityRarity) -> String {
        switch rarity {
        case .legendary: return "crown.fill"
        case .mythical: return "wand.and.stars"
        case .ultraBeast: return "hexagon.fill"
        case .standard, .unknown: return "viewfinder.circle.fill"
        }
    }

}
