import SwiftUI
import StrandDesign

/// Presentation only: the stored scores and the app-wide Effort conversion remain authoritative.
struct RhythmTodayScorePresentation: Equatable {
    enum Kind: String, CaseIterable {
        case sleep, recovery, strain

        var title: String {
            switch self {
            case .sleep: return String(localized: "Sleep")
            case .recovery: return String(localized: "Recovery")
            case .strain: return String(localized: "Strain")
            }
        }

        var accessibilityID: String { "rhythm.score.\(rawValue)" }

        var tint: Color {
            switch self {
            case .sleep: return StrandPalette.rhythmSleep
            case .recovery: return StrandPalette.rhythmRecovery
            case .strain: return StrandPalette.rhythmStrain
            }
        }

        var destination: TabRoute {
            switch self {
            case .sleep: return .sleep
            case .recovery: return .metric("recovery")
            case .strain: return .metric("strain")
            }
        }
    }

    let kind: Kind
    let storedValue: Double?

    private var validValue: Double? {
        guard let storedValue, storedValue.isFinite, (0...100).contains(storedValue) else { return nil }
        return storedValue
    }

    var valueLabel: String {
        guard let value = validValue else { return "—" }
        return kind == .strain
            ? UnitFormatter.effortDisplay(value, scale: .whoop)
            : String(Int(value.rounded()))
    }

    var fraction: Double? {
        validValue.map {
            kind == .strain ? UnitFormatter.effortValue($0, scale: .whoop) / 21 : $0 / 100
        }
    }

    var accessibilityValue: String {
        guard validValue != nil else { return String(localized: "Unavailable") }
        return kind == .strain
            ? String(localized: "\(valueLabel) out of 21")
            : String(localized: "\(valueLabel) out of 100")
    }

    static func recoveryHint(_ display: LiquidTodayView.ChargeDisplay) -> String {
        switch display {
        case .carried(_, let caption): return caption
        case .calibrating: return String(localized: "Calibrating")
        case .noData: return String(localized: "Unavailable")
        case .scored(let value): return StrandPalette.recoveryState(value)
        }
    }
}

/// Widths are proposed to the entire cells, not guessed from a screen size. The side rings' bottom
/// edges align with the larger centre ring; captions may grow freely at accessibility text sizes.
struct RhythmTodayScoreLayout: Layout {
    var spacing: CGFloat = NoopMetrics.space2

    static func columnWidths(availableWidth: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let side = max(0, availableWidth - spacing * 2) / 3.24
        return [side, side * 1.24, side]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? NoopMetrics.controlHeight * 7
        let widths = Self.columnWidths(availableWidth: width, spacing: spacing)
        let height = zip(subviews, widths).map { view, column in
            let measured = view.sizeThatFits(.init(width: column, height: nil))
            return measured.height + widths[1] - column
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.columnWidths(availableWidth: bounds.width, spacing: spacing)
        var x = bounds.minX
        for (view, column) in zip(subviews, widths) {
            view.place(at: CGPoint(x: x, y: bounds.minY + widths[1] - column),
                       anchor: .topLeading, proposal: .init(width: column, height: nil))
            x += column + spacing
        }
    }
}

struct RhythmTodayScoreCell: View {
    let score: RhythmTodayScorePresentation
    let hint: String
    let source: String?

    var body: some View {
        NavigationLink(value: score.kind.destination) {
            VStack(spacing: NoopMetrics.space2) {
                Circle()
                    .strokeBorder(score.kind.tint.opacity(0.14), lineWidth: NoopMetrics.space2)
                    .overlay {
                        if let fraction = score.fraction, fraction > 0 {
                            Circle()
                                .inset(by: NoopMetrics.space1)
                                .trim(from: 0, to: fraction)
                                .stroke(score.kind.tint, style: StrokeStyle(
                                    lineWidth: NoopMetrics.space2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Text(score.valueLabel)
                            .font(score.kind == .recovery ? StrandFont.display(48) : StrandFont.number(34))
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.45)
                            .padding(NoopMetrics.space3)
                    }
                Text(score.kind.title)
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(score.kind.accessibilityID)
        .accessibilityLabel(score.kind.title)
        .accessibilityValue(score.accessibilityValue)
        .accessibilityHint([hint, source.map { String(localized: "Source: \($0)") },
                            String(localized: "Opens score details")].compactMap { $0 }.joined(separator: ". "))
    }
}

struct RhythmTodayProgressBar: View {
    let fraction: Double?
    let tint: Color
    var height: CGFloat = NoopMetrics.space1

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    if let fraction, fraction.isFinite {
                        Capsule().fill(tint)
                            .frame(width: geometry.size.width * min(1, max(0, fraction)))
                    }
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}
