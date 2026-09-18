#if os(iOS)
import SwiftUI
import StrandDesign

struct RhythmMoreView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(MoreSectionPrefs.storageKey) private var expandedCSV = MoreSectionPrefs.defaultCSV
    @State private var search = ""

    var body: some View {
        ScreenScaffold(title: "All of your Ūrjas.", subtitle: "Familiar tools. A clearer place for each.",
                       onRefresh: { await repo.refresh() }) {
            searchField
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ForEach(MobileFeature.originalGroups) { group in
                    groupSection(group, collapsible: true)
                }
                ForEach(MobileFeature.additionalGroups) { group in
                    groupSection(group, collapsible: false)
                }
            } else {
                let results = MobileFeature.matching(search)
                Text("\(results.count) matching features")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .accessibilityIdentifier("rhythm.more.results")
                if results.isEmpty {
                    DataPendingNote(title: "No matching features",
                                    message: "Try a tool, metric or category, such as sleep, coach or sync.",
                                    symbol: "magnifyingglass")
                } else {
                    featureRows(results)
                }
            }
        }
        .accessibilityIdentifier("rhythm.more")
    }

    private var searchField: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "magnifyingglass").foregroundStyle(StrandPalette.textTertiary)
            TextField("Find any feature", text: $search)
                .font(StrandFont.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search features")
                .accessibilityIdentifier("rhythm.more.search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(minWidth: NoopMetrics.rhythmTapTarget, minHeight: NoopMetrics.rhythmTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear feature search")
            }
        }
        .padding(.horizontal, NoopMetrics.space3)
        .frame(minHeight: NoopMetrics.rhythmTapTarget + NoopMetrics.space2)
        .background(StrandPalette.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: NoopMetrics.space3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.space3).strokeBorder(StrandPalette.hairline))
    }

    private func groupSection(_ group: MobileFeatureGroup, collapsible: Bool) -> some View {
        let open = !collapsible || MoreSectionPrefs.decode(expandedCSV).contains(group.id)
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if collapsible {
                Button {
                    var expanded = MoreSectionPrefs.decode(expandedCSV)
                    if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
                    expandedCSV = MoreSectionPrefs.encode(expanded)
                } label: {
                    HStack {
                        Text(group.title).font(StrandFont.headline)
                        Spacer()
                        Text("\(group.features.count) tools").font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                    .frame(minHeight: NoopMetrics.rhythmTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.title)
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("rhythm.more.group.\(group.id)")
            } else {
                Text(group.title).font(StrandFont.headline).padding(.top, NoopMetrics.space2)
            }
            if open { featureRows(group.features) }
        }
    }

    private func featureRows(_ features: [MobileFeature]) -> some View {
        NoopCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(features) { feature in
                    RhythmFeatureRow(feature: feature)
                    if feature != features.last {
                        Divider().overlay(StrandPalette.hairline)
                            .padding(.horizontal, NoopMetrics.space4)
                    }
                }
            }
        }
    }
}

struct RhythmFeatureRow: View {
    let feature: MobileFeature

    var body: some View {
        NavigationLink(value: feature) {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: feature.symbol)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: NoopMetrics.space6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text(feature.title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Text(feature.subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(NoopMetrics.space4)
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.rhythmTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feature.title)
        .accessibilityHint(feature.subtitle)
        .accessibilityIdentifier("rhythm.feature.\(feature.rawValue)")
    }
}
#endif
