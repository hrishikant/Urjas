#if os(iOS)
import SwiftUI
import StrandDesign

private enum RhythmTab: Int, CaseIterable, Identifiable {
    case today, activity, sleep, health, more
    var id: Int { rawValue }
    var key: String {
        switch self {
        case .today: return "today"
        case .activity: return "activity"
        case .sleep: return "sleep"
        case .health: return "health"
        case .more: return "more"
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .today: return "Today"
        case .activity: return "Activity"
        case .sleep: return "Sleep"
        case .health: return "Health"
        case .more: return "More"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "house"
        case .activity: return "waveform.path.ecg"
        case .sleep: return "moon"
        case .health: return "heart"
        case .more: return "ellipsis"
        }
    }
}

struct RhythmRootTabView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: RhythmTab = .today
    @State private var paths = Array(repeating: NavigationPath(), count: RhythmTab.allCases.count)
    @State private var scrollSignals = Array(repeating: 0, count: RhythmTab.allCases.count)
    @State private var presentedFeature: MobileFeature?
    @State private var pendingFeature: MobileFeature?
    @State private var showQuickActions = false

    var body: some View {
        TabView(selection: $selection) {
            root(LiquidTodayView(), tab: .today)
            root(WorkoutsView(), tab: .activity)
            root(SleepView(), tab: .sleep)
            root(HealthView(), tab: .health)
            root(RhythmMoreView(), tab: .more)
        }
        .toolbar(.hidden, for: .tabBar)
        .simultaneousGesture(tabSwipeGesture,
                             including: paths[selection.rawValue].isEmpty ? .all : .subviews)
        .tint(StrandPalette.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .task {
            await repo.refresh()
            let backupRepo = repo
            Task.detached(priority: .utility) {
                await FolderBackup.catchUpIfDue(checkpoint: { await backupRepo.checkpointForBackup() })
            }
        }
        .sheet(item: $presentedFeature, onDismiss: finishPendingNavigation) { feature in
            NavigationStack {
                RhythmFeatureDestination(feature: feature)
                    .tabRouteDestinations(showNavigationBar: true)
                    .mobileFeatureDestinations()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { presentedFeature = nil }
                                .accessibilityIdentifier("rhythm.sheet.done")
                        }
                    }
            }
            .tint(StrandPalette.accent)
        }
        .sheet(isPresented: $showQuickActions, onDismiss: finishPendingNavigation) {
            NavigationStack {
                RhythmQuickActionsView()
                    .tabRouteDestinations(showNavigationBar: true)
                    .mobileFeatureDestinations()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showQuickActions = false }
                                .accessibilityIdentifier("rhythm.quick.done")
                        }
                    }
            }
            .tint(StrandPalette.accent)
        }
        .onChange(of: router.quickActionsRequested) { _, requested in
            guard requested else { return }
            router.quickActionsRequested = false
            showQuickActions = true
        }
        .onChange(of: router.requestedDestination) { _, destination in
            guard let destination else { return }
            let feature: MobileFeature
            switch destination {
            case .devices: feature = .devices
            case .insightsHub: feature = .insightsHub
            case .labBook: feature = .labBook
            case .fusedRecord: feature = .fusedRecord
            case .rhythm: feature = .rhythm
            case .trends: feature = .trends
            case .activeWorkout: feature = .live
            case .liveSession: feature = .liveSession
            case .journal: feature = .journal
            }
            router.requestedDestination = nil
            if presentedFeature != nil {
                pendingFeature = feature
                presentedFeature = nil
            } else if showQuickActions {
                pendingFeature = feature
                showQuickActions = false
            } else {
                paths[selection.rawValue].append(feature)
            }
        }
    }

    private func finishPendingNavigation() {
        if let feature = pendingFeature {
            pendingFeature = nil
            paths[selection.rawValue].append(feature)
        }
    }

    private func root<Content: View>(_ content: Content, tab: RhythmTab) -> some View {
        NavigationStack(path: $paths[tab.rawValue]) {
            VStack(spacing: 0) {
                RhythmAppHeader(onOpen: { presentedFeature = $0 },
                                onQuickActions: { showQuickActions = true })
                content
            }
            .navigationTitle(tab.title)
            .toolbar(.hidden, for: .navigationBar)
            .tabRouteDestinations(showNavigationBar: true)
            .mobileFeatureDestinations()
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
        }
        .environment(\.scrollToTopSignal, scrollSignals[tab.rawValue])
        .toolbar(.hidden, for: .tabBar)
        .tag(tab)
    }

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            guard selection != .today else { return }
            let dx = value.translation.width, dy = value.translation.height
            guard abs(dx) > 60, abs(dx) > abs(dy) * 1.6 else { return }
            let raw = min(RhythmTab.allCases.count - 1, max(0, selection.rawValue + (dx < 0 ? 1 : -1)))
            if let next = RhythmTab(rawValue: raw), next != selection {
                withAnimation(reduceMotion ? nil : StrandMotion.interactive) { selection = next }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: NoopMetrics.space1) {
            ForEach(RhythmTab.allCases) { tab in
                Button {
                    if selection == tab {
                        Task { await repo.refresh() }
                        if paths[tab.rawValue].isEmpty {
                            scrollSignals[tab.rawValue] += 1
                        } else {
                            paths[tab.rawValue] = NavigationPath()
                        }
                    } else {
                        withAnimation(reduceMotion ? nil : StrandMotion.interactive) { selection = tab }
                    }
                } label: {
                    VStack(spacing: NoopMetrics.space1) {
                        Image(systemName: tab.symbol)
                            .font(StrandFont.rounded(NoopMetrics.rhythmIconSize, weight: .medium))
                        Text(tab.title)
                            .font(StrandFont.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? StrandPalette.accent : StrandPalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: NoopMetrics.rhythmTabHeight)
                    .background(selection == tab ? StrandPalette.accentMuted : .clear,
                                in: RoundedRectangle(cornerRadius: NoopMetrics.space3, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("rhythm.tab.\(tab.key)")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, NoopMetrics.space3)
        .padding(.top, NoopMetrics.space2)
        .background {
            StrandPalette.surfaceRaised.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
        }
    }
}

private struct RhythmAppHeader: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(AppearanceMode.storageKey) private var appearanceRaw = AppearanceMode.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    let onOpen: (MobileFeature) -> Void
    let onQuickActions: () -> Void

    var body: some View {
        HStack(spacing: NoopMetrics.space2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoopMetrics.space2) {
                    logo
                    Text("Ūrjas")
                        .font(StrandFont.rounded(NoopMetrics.space6, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .fixedSize()
                logo
            }
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ūrjas")
            Spacer(minLength: 0)
            RhythmSyncButton { onOpen(.devices) }
            Button {
                appearanceRaw = colorScheme == .dark ? AppearanceMode.light.rawValue : AppearanceMode.dark.rawValue
            } label: {
                Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                    .font(StrandFont.headline)
                    .frame(width: NoopMetrics.rhythmTapTarget, height: NoopMetrics.rhythmTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(colorScheme == .dark ? "Switch to light theme" : "Switch to dark theme")
            .accessibilityIdentifier("rhythm.theme")
            Button(action: onQuickActions) {
                Image(systemName: "plus")
                    .font(StrandFont.headline)
                    .frame(width: NoopMetrics.rhythmTapTarget, height: NoopMetrics.rhythmTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Quick actions")
            .accessibilityIdentifier("rhythm.quick")
            Button { onOpen(.settings) } label: {
                ProfileAvatarView(imageData: profile.avatarImageData, size: NoopMetrics.rhythmAvatarSize)
                    .frame(width: NoopMetrics.rhythmTapTarget, height: NoopMetrics.rhythmTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Profile and settings")
            .accessibilityIdentifier("rhythm.profile")
        }
        .buttonStyle(.plain)
        .foregroundStyle(StrandPalette.textSecondary)
        .padding(.horizontal, NoopMetrics.rhythmSideInset)
        .padding(.vertical, NoopMetrics.space1)
        .background(StrandPalette.surfaceBase)
    }

    private var logo: some View {
        Text("Ū")
            .font(StrandFont.headline)
            .foregroundStyle(StrandPalette.rhythmButtonText)
            .frame(width: NoopMetrics.rhythmLogoSize, height: NoopMetrics.rhythmLogoSize)
            .background(StrandPalette.rhythmButtonFill,
                        in: RoundedRectangle(cornerRadius: NoopMetrics.space2))
    }
}

/// Live publications are isolated here, rather than invalidating the whole tab shell on every HR tick.
private struct RhythmSyncButton: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var intelligence: IntelligenceEngine
    let onOpen: () -> Void

    private var label: String {
        if live.lastSyncError != nil { return String(localized: "Sync needs attention") }
        if live.backfilling { return String(localized: "Receiving history") }
        if intelligence.computing { return String(localized: "Analysing data") }
        if !live.connected { return String(localized: "Band offline") }
        if !live.encryptedBond && !live.streamingLiveHR { return String(localized: "Pairing needed") }
        if let last = live.lastSyncedAt { return String(localized: "Synced \(relativeAgo(last))") }
        return String(localized: "Band connected")
    }

    var body: some View {
        Button(action: onOpen) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoopMetrics.space1) {
                    dot
                    Text(label).font(StrandFont.caption).lineLimit(1)
                }
                HStack(spacing: NoopMetrics.space1) {
                    dot
                    Text("Band").font(StrandFont.caption)
                }
                dot
            }
            .frame(minWidth: NoopMetrics.rhythmTapTarget, minHeight: NoopMetrics.rhythmTapTarget)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
        .accessibilityHint("Open band and sync details")
        .accessibilityIdentifier("rhythm.sync")
    }

    private var dot: some View {
        Circle()
            .fill(live.lastSyncError != nil ? StrandPalette.statusWarning :
                    live.connected ? StrandPalette.accent : StrandPalette.textTertiary)
            .frame(width: NoopMetrics.space2, height: NoopMetrics.space2)
    }
}

private struct RhythmQuickActionsView: View {
    var body: some View {
        ScreenScaffold(title: "What would feel good?", subtitle: "Quick actions") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: NoopMetrics.space3) {
                quickLink("Live heart rate", symbol: "waveform.path.ecg", feature: .live)
                NavigationLink {
                    WorkoutsView(initialAction: .start)
                } label: {
                    tile("Start workout", symbol: "play")
                }
                .accessibilityIdentifier("rhythm.quick.start")
                quickLink("Log journal", symbol: "square.and.pencil", feature: .journal)
                quickLink("Breathe", symbol: "wind", feature: .breathe)
            }
            .buttonStyle(.plain)
        }
    }

    private func quickLink(_ title: LocalizedStringKey, symbol: String, feature: MobileFeature) -> some View {
        NavigationLink(value: feature) { tile(title, symbol: symbol) }
            .accessibilityIdentifier("rhythm.quick.\(feature.rawValue)")
    }

    private func tile(_ title: LocalizedStringKey, symbol: String) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Image(systemName: symbol).foregroundStyle(StrandPalette.accent)
                    .font(StrandFont.title2)
                Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: NoopMetrics.rhythmTapTarget, alignment: .leading)
        }
    }
}
#endif
