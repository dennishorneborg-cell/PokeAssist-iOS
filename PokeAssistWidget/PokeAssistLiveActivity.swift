import ActivityKit
import SwiftUI
import WidgetKit

private struct CompactActivityBadge: Identifiable {
    let id: String
    let symbol: String
    let color: Color
    var text: String?
}

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
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
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
        // Compact leading has a fixed, very narrow system-provided width.
        // Keep the most useful five badges at most; otherwise SwiftUI clips
        // trailing symbols and they appear as colored slivers.
        let badges = compactBadgeModels(presentation).prefix(5)
        HStack(spacing: 1) {
            ForEach(Array(badges)) { badge in
                if let text = badge.text {
                    Text(text)
                        .font(.system(size: compactBadgePointSize(presentation) * 0.75, weight: .black, design: .rounded))
                        .foregroundStyle(badge.color)
                } else {
                    Image(systemName: badge.symbol)
                        .foregroundStyle(badge.color)
                }
            }
        }
        .font(.system(size: compactBadgePointSize(presentation), weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityLabel("PokeAssist status and detected traits")
    }

    @ViewBuilder
    private func minimalBadges(_ presentation: PokeAssistActivityPresentation) -> some View {
        // ScreenCaptureKit's recording indicator makes iOS choose the minimal
        // Live Activity presentation. Scale the SF Symbols to the available
        // trait and appraisal-grade count so they stay legible.
        HStack(spacing: 0) {
            Image(systemName: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill")
                .foregroundStyle(.green)

            if let rating = ivRatingBadge(presentation) {
                Image(systemName: rating.symbol)
                    .foregroundStyle(rating.color)
            }

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
                    .font(.system(size: minimalBadgePointSize(presentation) * 0.75, weight: .black, design: .rounded))
                    .foregroundStyle(.cyan)
            }
            if presentation.pvpCandidate {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: minimalBadgePointSize(presentation), weight: .bold))
        .lineLimit(1)
        .accessibilityLabel("PokeAssist status and detected traits")
    }

    private func badgeCount(_ presentation: PokeAssistActivityPresentation) -> Int {
        1
            + (ivRatingBadge(presentation) == nil ? 0 : 1)
            + (presentation.shinyDetected ? 1 : 0)
            + (presentation.eventDetected ? 1 : 0)
            + (presentation.rarity.isProtected ? 1 : 0)
            + (presentation.dynamaxDetected ? 1 : 0)
            + (presentation.size != .none ? 1 : 0)
            + (presentation.pvpCandidate ? 1 : 0)
    }

    private func compactBadgePointSize(_ presentation: PokeAssistActivityPresentation) -> CGFloat {
        switch min(badgeCount(presentation), 5) {
        case 1...2: return 12
        case 3: return 10
        case 4: return 8
        default: return 6.5
        }
    }

    private func compactBadgeModels(_ presentation: PokeAssistActivityPresentation) -> [CompactActivityBadge] {
        var badges = [CompactActivityBadge(
            id: "mode",
            symbol: presentation.mode == .appraisal ? "chart.bar.fill" : "viewfinder.circle.fill",
            color: .green
        )]

        if let rating = ivRatingBadge(presentation) {
            badges.append(CompactActivityBadge(id: "iv", symbol: rating.symbol, color: rating.color))
        }
        if presentation.shinyDetected {
            badges.append(CompactActivityBadge(id: "shiny", symbol: "sparkles", color: .yellow))
        }
        if presentation.eventDetected {
            badges.append(CompactActivityBadge(id: "event", symbol: "party.popper.fill", color: .purple))
        }
        if presentation.rarity.isProtected {
            badges.append(CompactActivityBadge(id: "rarity", symbol: raritySymbol(presentation.rarity), color: .orange))
        }
        if presentation.dynamaxDetected {
            badges.append(CompactActivityBadge(
                id: "dynamax",
                symbol: "arrow.up.left.and.arrow.down.right",
                color: .pink
            ))
        }
        if presentation.size != .none {
            badges.append(CompactActivityBadge(
                id: "size",
                symbol: "",
                color: .cyan,
                text: presentation.size == .xxl ? "L" : "S"
            ))
        }
        if presentation.pvpCandidate {
            badges.append(CompactActivityBadge(id: "pvp", symbol: "shield.fill", color: .blue))
        }
        return badges
    }

    private func minimalBadgePointSize(_ presentation: PokeAssistActivityPresentation) -> CGFloat {
        switch badgeCount(presentation) {
        case 1...3: return 11
        case 4: return 9.5
        case 5: return 8.5
        default: return 6.5
        }
    }

    private func ivRatingBadge(
        _ presentation: PokeAssistActivityPresentation
    ) -> (symbol: String, color: Color)? {
        guard presentation.mode == .appraisal,
              let percentage = presentation.ivPercentage else {
            return nil
        }

        switch percentage {
        case 100:
            return ("star.fill", .yellow)
        case 90..<100:
            return ("star.leadinghalf.filled", .orange)
        case 0..<80:
            return ("chart.bar.fill", .red)
        default:
            return nil
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

    private func raritySymbol(_ rarity: PokeAssistActivityRarity) -> String {
        switch rarity {
        case .legendary: return "crown.fill"
        case .mythical: return "wand.and.stars"
        case .ultraBeast: return "hexagon.fill"
        case .standard, .unknown: return "viewfinder.circle.fill"
        }
    }

}
