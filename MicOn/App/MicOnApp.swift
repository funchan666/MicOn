import SwiftUI
import OSLog

@main
struct MicOnApp: App {
    @AppStorage(AppLanguage.preferenceKey) private var languageCode = AppLanguage.systemSelection
    @Environment(\.scenePhase) private var appPhase
    @State private var systemLanguage = AppLanguage.systemLanguage()
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? systemLanguage }
    @StateObject private var api: APIClient
    @StateObject private var library: LibraryStore
    @StateObject private var quota: QuotaStore
    @StateObject private var commerce: CommerceStore
    @StateObject private var offline: OfflineStore
    @StateObject private var ads: RewardedAds
    @StateObject private var accountAccess = AccountAccessFlow()
    init() {
        let api = APIClient()
        let quota = QuotaStore()
        _api = StateObject(wrappedValue: api)
        _library = StateObject(wrappedValue: LibraryStore())
        _quota = StateObject(wrappedValue: quota)
        let commerce = CommerceStore(api: api, quota: quota)
        _commerce = StateObject(wrappedValue: commerce)
        _offline = StateObject(wrappedValue: OfflineStore(api: api, quota: quota, commerce: commerce))
        _ads = StateObject(wrappedValue: RewardedAds())
    }
    var body: some Scene {
        WindowGroup {
            MicOnStartupHost().environmentObject(api).environmentObject(library)
                .environmentObject(quota).environmentObject(commerce).environmentObject(ads).environmentObject(offline)
                .environmentObject(accountAccess)
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection, language.direction)
                .font(.booth(.body))
                .preferredColorScheme(.dark).tint(MicOnStyle.accent)
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    systemLanguage = AppLanguage.systemLanguage()
                }
                .onChange(of: appPhase) { _, phase in
                    if phase == .active { systemLanguage = AppLanguage.systemLanguage() }
                }
        }
    }
}

// Keeps the original splash visible during the bounded cold-start ad opportunity.
// Guest authentication prepares configuration and opens the app directly.
struct MicOnStartupHost: View {
    @EnvironmentObject private var ads: RewardedAds
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var accountAccess: AccountAccessFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false
    @State private var startupBegan = ContinuousClock.now

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            // Mount once so local content and authentication prepare while the
            // bounded app-open opportunity runs, without rebuilding navigation.
            MicOnRootView()
                .allowsHitTesting(finished)
                .accessibilityHidden(!finished)
            if !finished {
                MicOnStartupView().transition(.opacity)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !finished else { return }
            ads.beginStartup(commerce: commerce, accountAccess: accountAccess)
        }
        .onReceive(ads.$startupFinished) { complete in
            if complete, !finished {
                Logger(subsystem: "app.micon", category: "Startup")
                    .info("Home became interactive after \(startupBegan.duration(to: .now).description, privacy: .public)")
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { finished = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { ads.didEnterBackground() }
            if phase == .active, finished {
                ads.didBecomeActive(commerce: commerce, accountAccess: accountAccess)
            }
        }
    }
}

struct MicOnStartupView: View {
    var body: some View {
        // Same centred mark as LaunchScreen.storyboard, so the hand-off does not jump.
        MicOnIllustration(name: "LaunchMark", height: 108).frame(width: 108)
            .overlay(alignment: .bottom) { ProgressView().tint(MicOnStyle.accent).offset(y: 52) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LocalizedStringKey("MicOn is starting"))
            .background(Color("LaunchBackground").ignoresSafeArea())
    }
}

enum MicOnTab: Int, CaseIterable, Hashable {
    case home, discover, library, me
    var name: String { ["Listen back", "Discover", "Library", "Me"][rawValue] }
    // Original single-colour tab artwork; the system tab bar tints it.
    var artwork: String { ["TabHome", "TabDiscover", "TabLibrary", "TabMe"][rawValue] }
}

private struct MicOnTabItem: View {
    let tab: MicOnTab
    @Environment(\.locale) private var locale
    var body: some View {
        Label {
            Text(verbatim: L10n.display(tab.name, language: AppLanguage.from(locale)))
        } icon: {
            Image(tab.artwork).renderingMode(.template)
        }
    }
}

private struct MicOnTabBar: View {
    @Binding var selection: MicOnTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(MicOnTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(5)
        .studioGlass(in: RoundedRectangle(cornerRadius: 25))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 5)
        .frame(maxWidth: 500)
        .padding(.horizontal, 14)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selection)
    }

    private func tabButton(_ tab: MicOnTab) -> some View {
        let selected = selection == tab
        return Button { selection = tab } label: {
            VStack(spacing: 4) {
                TintedArtwork(name: tab.artwork, tint: selected ? MicOnStyle.ink : MicOnStyle.paper)
                    .frame(width: 26, height: 26)
                    .frame(width: 46, height: 31)
                    .background {
                        if selected {
                            Capsule().fill(MicOnStyle.accent)
                                .matchedGeometryEffect(id: "active-tab", in: highlight)
                        }
                    }
                LocalizedText(tab.name)
                    .font(.booth(.caption2, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? MicOnStyle.paper : MicOnStyle.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2).padding(.vertical, 4)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 54, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(LocalizedStringKey(tab.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tab.\(tab.name.lowercased())")
    }
}

private extension View {
    func miconTab(_ tab: MicOnTab, systemBar: Bool) -> some View {
        tabItem { MicOnTabItem(tab: tab) }
            .tag(tab)
            .toolbar(systemBar ? .visible : .hidden, for: .tabBar)
    }
}

struct MicOnRootView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var offline: OfflineStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.self) private var environment
    @SceneStorage("root.tab") private var tab: MicOnTab = .home
    @State private var editing: PracticeRecording?
    @SceneStorage("home.linkDraft") private var linkDraft = ""
    @State private var libraryFilter = "Saved"
    @State private var showingTools = false
    var body: some View {
        GeometryReader { container in
            let systemBar = usesSystemTabBar(in: container)
            tabPages(systemBar: systemBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !systemBar { MicOnTabBar(selection: $tab) }
                }
        }
        .tint(MicOnStyle.accent)
        .foregroundStyle(.white)
            .sheet(item: $editing) { EditorSheet(initialMovie: $0) }
            .sheet(isPresented: $showingTools) {
                VStack(spacing: 0) {
                    SheetHeading(title: "Review a singing take") { showingTools = false }
                    ToolsView()
                }.miconScreenBackground().modifier(AccountBusyModifier())
            }
            .overlay(alignment: .top) {
                if tab != .discover { DownloadCompletionNotice().padding(.top, 8) }
            }
            .task(id: library.downloadsRequest) {
                guard library.downloadsRequest != nil else { return }
                // Full-screen players dismiss first; then move the underlying tab.
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                editing = nil
                libraryFilter = "Downloads"
                tab = .library
            }
            .task(id: api.session?.userId.value) {
                guard api.session != nil else { return }
                if !commerce.rightsVerified || commerce.release == nil { await commerce.refresh() }
                await offline.resumePending()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { quota.resetIfNeeded() }
            }
            .overlay(alignment: .top) {
                if let message = library.error {
                    HStack {
                        LocalizedText(message).font(.booth(.subheadline))
                        IconButton(symbol: .close, label: "Dismiss message") { library.error = nil }
                    }.padding(14).background(MicOnStyle.raised, in: RoundedRectangle(cornerRadius: 18)).padding()
                }
            }
            .modifier(AccountBusyModifier())
    }

    private func tabPages(systemBar: Bool) -> some View {
        TabView(selection: $tab) {
            HomeView(openAccount: { tab = .me }, discover: { tab = .discover }, openTools: { showingTools = true }, link: $linkDraft)
                .miconTab(.home, systemBar: systemBar)
            // Mount the feed only while selected: it owns players and quota admission.
            Group {
                if tab == .discover { DiscoverView(onExit: { tab = .home }) }
                else { MicOnStyle.background.ignoresSafeArea() }
            }.miconTab(.discover, systemBar: systemBar)
            LibraryView(edit: { editing = $0 }, filter: $libraryFilter)
                .miconTab(.library, systemBar: systemBar)
            AccountView().miconTab(.me, systemBar: systemBar)
        }
    }

    private func usesSystemTabBar(in container: GeometryProxy) -> Bool {
        if environment.dynamicTypeSize.isAccessibilitySize || container.size.width < 264 { return true }
        guard #available(iOS 27.1, *) else { return false }
        if environment.toolbarVerticalEdge != nil { return true }
        // Only a fold or camera region touching the dock needs to change the bar.
        let width = min(container.size.width, 528)
        let height = min(container.size.height, 88)
        let dock = CGRect(x: (container.size.width - width) / 2, y: container.size.height - height,
                          width: width, height: height)
        let regions = container.reservedRegions(kind: .division) + container.reservedRegions(kind: .occlusion)
        return regions.contains { $0.isActive && $0.frame.intersects(dock) }
    }
}

// A network recovery surface, not a second login or consent gate.
struct ConnectionPanel: View {
    var showsArtwork = true
    @EnvironmentObject private var api: APIClient
    @State private var error: String?
    @State private var connecting = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            if showsArtwork { BoothArtwork(kind: .studio, height: 170) }
            if let error {
                MessagePanel(title: "Let’s reconnect.", message: error)
                ActionButton(title: "Try again", busy: connecting) { attempt += 1 }
            } else {
                AccountLoadingIndicator(title: "Setting up your practice room…")
            }
            PolicyLinks()
        }
        .frame(maxWidth: 440).frame(maxWidth: .infinity)
        .task(id: attempt) {
            guard api.session == nil else { return }
            connecting = true
            error = nil
            defer { connecting = false }
            do { try await api.prepareVisitor() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
