import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    var openAccount: () -> Void
    var discover: () -> Void
    var openTools: () -> Void
    @Binding var link: String
    @State private var error: String?
    @State private var linkFailure = ""
    @State private var showingLinkFailure = false
    @State private var channel: ChannelRoute?
    @State private var searchRequest: LessonSearch?
    @State private var paywall = false
    @State private var channels: [LandingInfo] = []
    @State private var channelRetry = 0
    @State private var showingLinkGuide = false
    @State private var showingGuide = false
    @State private var showingJournal = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var takePlayer = PlaybackController()
    @State private var listeningFileID: UUID?
    @State private var reviewingTake: PracticeRecording?
    @State private var openLessonFeedAfterDismissal = false
    @State private var showingLink = false
    @State private var pendingLinkSearch: LessonSearch?
    @State private var composerError: String?
    @FocusState private var focused: Bool
    var body: some View {
        let request = ChannelRequest(links: commerce.release?.lcList?["us"] ?? [], attempt: channelRetry)
        ScrollView {
            VStack(spacing: 0) {
                listeningCover
                VStack(alignment: .leading, spacing: 24) {
                    lessonShortcut
                    recentTakesSection
                    practiceShortcuts
                    connection
                    techniqueQueue
                    recentLinks
                }.miconPage()
            }
        }.scrollClipDisabled()
            .miconScreenBackground().scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showingLink, onDismiss: openPendingLesson) {
                VStack(spacing: 0) {
                    SheetHeading(title: "Open a singing lesson") { showingLink = false }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            lessonMixer
                            if let composerError { ErrorNote(message: composerError) }
                            if api.session == nil { ConnectionPanel() }
                        }.miconPage()
                    }.scrollDismissesKeyboard(.interactively)
                }.miconScreenBackground()
                    .dismissKeyboardOnOutsideTap($focused, scope: "home-link-input")
                    .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            }
            .sheet(item: $channel) { ChannelView(route: $0) }
            .fullScreenCover(item: $searchRequest) { request in
                DiscoverView(initialSearch: request.query, canDismiss: true) { query, clip in
                    library.record(link: query, title: clip.title)
                }
            }
            .fullScreenCover(isPresented: $showingLinkFailure) {
                AccountDecisionDialog(title: "Couldn’t open this link", message: linkFailure,
                                      confirmTitle: "Back to link", confirm: { showingLinkFailure = false })
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $paywall) { MembershipView() }
            .sheet(isPresented: $showingJournal) { VocalPracticeView() }
            .sheet(item: $reviewingTake) { EditorSheet(initialMovie: $0) }
            .sheet(isPresented: $showingGuide) { VocalGuideView() }
            .onDisappear { takePlayer.pause() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { takePlayer.pause() }
            }
            .onChange(of: api.session?.userId.value) { _, _ in takePlayer.pause() }
            .onChange(of: library.movies) { _, movies in
                if let listeningFileID, !movies.contains(where: { $0.id == listeningFileID }) {
                    takePlayer.release()
                    self.listeningFileID = nil
                }
            }
            .task(id: request) {
                guard !Task.isCancelled else { return }
                channels = []
                error = nil
                guard !request.links.isEmpty else { return }
                do {
                    let result = try await api.channels(links: request.links)
                    if !Task.isCancelled { channels = result }
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription }
                }
            }
    }

    private var listeningCover: some View {
        StudioCover(artwork: "ListenCover", height: 222...458, ratio: 1.0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Spacer(minLength: 36)
                CoverTitle(title: "Listen back", size: 66)
                reviewAction
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                wordmark
                Spacer(minLength: 8)
                headerActions
            }
            VStack(alignment: .leading, spacing: 6) {
                wordmark
                headerActions
            }
        }
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            TintedArtwork(name: "TabHome", tint: MicOnStyle.accent).frame(width: 27, height: 21)
            Text(verbatim: "MicOn").font(.booth(.headline, weight: .bold))
                .foregroundStyle(MicOnStyle.paper)
        }.fixedSize()
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                takePlayer.pause()
                paywall = true
            } label: {
                LocalizedText(commerce.premium ? "Plus" : "Get Plus")
                    .font(.booth(.footnote, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(MicOnStyle.paper)
                    .studioGlass(in: Capsule())
                    .contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            IconButton(symbol: .settings, label: "Open Me and account settings") {
                takePlayer.pause()
                openAccount()
            }.studioGlass(in: Capsule())
        }
    }

    @ViewBuilder private var connection: some View {
        if api.session == nil { ConnectionPanel(showsArtwork: false) }
        if let error {
            MessagePanel(title: "Couldn’t load lesson collections", message: error, actionTitle: "Try again") {
                channelRetry += 1
            }
        }
    }

    private var reviewAction: some View {
        Button {
            takePlayer.pause()
            if let movie = library.movies.first(where: { $0.id == listeningFileID }) {
                reviewingTake = movie
            } else {
                openTools()
            }
        } label: {
            HStack(spacing: 10) {
                Glyph(symbol: .edit, size: 19, tint: MicOnStyle.ink)
                LocalizedText("Review a singing take").font(.booth(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 17).padding(.vertical, 11)
            .frame(minHeight: 52)
            .foregroundStyle(MicOnStyle.ink)
            .background(MicOnStyle.accent, in: Capsule())
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("home.reviewTake")
    }

    private var lessonShortcut: some View {
        Button {
            takePlayer.pause()
            showingLink = true
        } label: {
            HStack(spacing: 13) {
                Glyph(symbol: .link, size: 18, tint: MicOnStyle.accent)
                    .frame(width: 40, height: 40)
                    .background(MicOnStyle.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Open a singing lesson").font(.booth(.headline))
                        .foregroundStyle(MicOnStyle.paper)
                    LocalizedText("MicOn link or lesson code").font(.booth(.footnote))
                        .foregroundStyle(MicOnStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 12, tint: MicOnStyle.accent).rotationEffect(.degrees(180))
            }.padding(12).frame(minHeight: 64)
                .studioGlass(in: RoundedRectangle(cornerRadius: 22))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("home.showLink")
    }

    private var recentTakesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText("Recent imports").font(.booth(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let active = library.movies.first(where: { $0.id == listeningFileID }) {
                if !recentTakes.contains(where: { $0.id == active.id }) {
                    takeButton(active)
                }
                if let message = takePlayer.error {
                    ErrorNote(message: message)
                } else if takePlayer.isLoading {
                    LocalizedText("Preparing preview…").font(.booth(.caption))
                        .foregroundStyle(MicOnStyle.secondary)
                }
            }
            if recentTakes.isEmpty {
                LocalizedText("Choose a clip from your device. We’ll keep your original untouched.")
                    .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentTakes) { movie in
                        Divider().overlay(MicOnStyle.line)
                        takeButton(movie)
                    }
                }
            }
        }
    }

    private var recentTakes: [PracticeRecording] {
        Array(library.movies.filter { !$0.isExport }.prefix(5))
    }

    private var practiceShortcuts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(MicOnStyle.line)
            Button {
                takePlayer.pause()
                showingJournal = true
            } label: {
                HStack(spacing: 13) {
                    Glyph(symbol: .edit, size: 19, tint: MicOnStyle.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        LocalizedText("Singing log").font(.booth(.headline))
                        LocalizedText("Keep a record of phrasing, key and how each take felt.")
                            .font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Glyph(symbol: .back, size: 12, tint: MicOnStyle.accent).rotationEffect(.degrees(180))
                }.padding(.vertical, 12).frame(minHeight: 50)
                    .foregroundStyle(MicOnStyle.paper).contentShape(Rectangle())
            }.buttonStyle(PressStyle()).accessibilityIdentifier("practice.openJournal")
            Divider().overlay(MicOnStyle.line)
            VocalGuideEntry(compact: true) {
                takePlayer.pause()
                showingGuide = true
            }
            Divider().overlay(MicOnStyle.line)
        }
    }

    private func takeButton(_ movie: PracticeRecording) -> some View {
        let playing = listeningFileID == movie.id && takePlayer.intendsPlayback
        return Button { playTake(movie) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: movie.title).font(.booth(.headline))
                        .fixedSize(horizontal: false, vertical: true)
                    LocalizedDateText(date: movie.date).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Glyph(symbol: playing ? .pause : .play, size: 17, tint: playing ? MicOnStyle.ink : MicOnStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(playing ? MicOnStyle.accent : MicOnStyle.surface, in: Circle())
            }.padding(.vertical, 6).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel(Text(verbatim: movie.title))
            .accessibilityHint(Text(playing ? "Pause" : "Play"))
            .accessibilityAddTraits(listeningFileID == movie.id ? .isSelected : [])
    }

    private func playTake(_ movie: PracticeRecording) {
        let url = library.url(for: movie)
        if takePlayer.loadedURL == url, takePlayer.error == nil {
            takePlayer.toggle()
        } else {
            listeningFileID = movie.id
            takePlayer.load(url, autoplay: true)
        }
    }

    @ViewBuilder private var techniqueQueue: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                LocalizedText("Karaoke lesson collections").font(.booth(.title2, display: true))
                    .accessibilityAddTraits(.isHeader)
                ForEach(channels.indices, id: \.self) { index in
                    let item = channels[index]
                    if let info = item.extraInfo, let title = info.channelName, let short = info.externalLinks {
                        Divider().overlay(MicOnStyle.line)
                        Button {
                            takePlayer.pause()
                            channel = ChannelRoute(link: short, title: title)
                        } label: {
                            HStack(spacing: 10) {
                                Glyph(symbol: .play, size: 14, tint: MicOnStyle.accent)
                                Text(verbatim: title).font(.booth(.headline))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let count = info.videoFileCount {
                                    Text(count, format: .number).font(.booth(.caption)).monospacedDigit()
                                        .foregroundStyle(MicOnStyle.secondary)
                                        .accessibilityLabel(Text(verbatim: L10n.display("\(count) videos")))
                                }
                            }.frame(minHeight: 46).contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    private func openPendingLesson() {
        composerError = nil
        if openLessonFeedAfterDismissal {
            openLessonFeedAfterDismissal = false
            discover()
            return
        }
        guard let request = pendingLinkSearch else { return }
        pendingLinkSearch = nil
        searchRequest = request
    }

    private var lessonMixer: some View {
        VStack(alignment: .leading, spacing: 12) {
            linkField
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { playLesson; pasteButton }
                VStack(alignment: .leading, spacing: 8) { playLesson; pasteButton }
            }
            allowanceLabel
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { lessonHelp; lessonFeed }
                VStack(alignment: .leading, spacing: 8) { lessonHelp; lessonFeed }
            }
        }.padding(.vertical, 4)
    }

    private var lessonHelp: some View {
        Button { showingLinkGuide = true } label: {
            LocalizedText("How to").font(.booth(.footnote, weight: .semibold))
                .foregroundStyle(MicOnStyle.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("home.linkHelp")
    }

    private var lessonFeed: some View {
        Button {
            openLessonFeedAfterDismissal = true
            showingLink = false
        } label: {
            LocalizedText("Watch tutorials").font(.booth(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .underline().foregroundStyle(MicOnStyle.accent)
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private var playLesson: some View {
        Button(action: resolve) {
            HStack(spacing: 10) {
                Glyph(symbol: .play, size: 16, tint: MicOnStyle.ink)
                LocalizedText("Open lesson").font(.booth(.headline, display: true))
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 48)
                .foregroundStyle(MicOnStyle.ink)
                .background(MicOnStyle.accent, in: Capsule())
                .contentShape(Rectangle())
        }.buttonStyle(ComposerPressStyle()).disabled(!canOpenLink)
            .accessibilityIdentifier("home.openLesson")
    }

    private var linkField: some View {
        HStack(spacing: 0) {
            TextField("MicOn link or lesson code", text: $link, axis: .vertical)
                .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.paper)
                .tint(MicOnStyle.paper)
                .padding(.leading, 14).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(LocalizedStringKey("MicOn link or lesson code"))
            if !link.isEmpty {
                Button {
                    link = ""
                    composerError = nil
                    focused = true
                } label: {
                    Glyph(symbol: .close, size: 13, tint: MicOnStyle.paper)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(ComposerPressStyle())
                    .accessibilityLabel(LocalizedStringKey("Clear link"))
                    .accessibilityIdentifier("home.clearLink")
            }
        }
            // Link input and its clear action stay together, including when
            // the outside-tap handler decides whether to dismiss the keyboard.
            .padding(.trailing, link.isEmpty ? 14 : 6)
            .environment(\.layoutDirection, .leftToRight)
            .background(MicOnStyle.raised, in: RoundedRectangle(cornerRadius: 14))
            .keyboardInputRegion("home-link-input")
    }

    private var canOpenLink: Bool { searchRequest == nil && link.nilIfBlank != nil }
    @ViewBuilder private var allowanceLabel: some View {
        if api.session != nil {
            LocalizedText(quota.usage == nil ? "Loading…" : commerce.premium || quota.unlimited ? "Unlimited viewing today" : "\(quota.watchesLeft) views left today")
                .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var pasteButton: some View {
        Button(action: pasteCopiedLink) {
            LocalizedText("Paste").font(.booth(.footnote, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .frame(minHeight: 44)
                .foregroundStyle(MicOnStyle.ink)
                .background(MicOnStyle.mist, in: Capsule())
                .contentShape(Rectangle())
        }.buttonStyle(ComposerPressStyle())
            .accessibilityIdentifier("home.pasteLink")
    }
    private func pasteCopiedLink() {
        guard let text = UIPasteboard.general.string, text.nilIfBlank != nil else {
            showLinkFailure("Copy a MicOn link or lesson code first, then tap Paste.")
            return
        }
        composerError = nil
        link = text
    }
    @ViewBuilder private var recentLinks: some View {
        if !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LocalizedText("Recently opened").font(.booth(.headline))
                    Spacer()
                    Button("Clear") { library.clearHistory() }
                        .buttonStyle(MatteActionStyle())
                }
                ForEach(library.history.prefix(5)) { visit in
                    HStack {
                        Button { link = visit.link; resolve() } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: visit.title).font(.booth(.headline)).lineLimit(1)
                                Text(verbatim: visit.link).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(PressStyle()).disabled(searchRequest != nil)
                        IconButton(symbol: .close, label: "Remove history item") { library.removeVisit(visit) }
                    }
                }
            }
        }
    }
    private func resolve() {
        guard let text = link.nilIfBlank, searchRequest == nil else { return }
        takePlayer.pause()
        focused = false
        guard api.session != nil else { showLinkFailure("Your connection is not ready yet. Please try again."); return }
        // Preserve exactly what was entered. Search owns loading, errors and cursor
        // pagination; do not fall back to the old landing-page resolver.
        let request = LessonSearch(query: text)
        if showingLink {
            pendingLinkSearch = request
            showingLink = false
        } else {
            searchRequest = request
        }
    }
    private func showLinkFailure(_ message: String) {
        if showingLink {
            composerError = message
            return
        }
        linkFailure = message
        showingLinkFailure = true
    }
}

// Disabled artwork already has its own legible palette; do not fade the entire
// button into the paper surface as the shared legacy PressStyle does.
private struct ComposerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct LessonSearch: Identifiable {
    let id = UUID()
    let query: String
}

private struct ChannelRequest: Equatable {
    let links: [String]
    let attempt: Int
}

struct ChannelView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    let route: ChannelRoute
    @State private var items: [RemoteLessonFile] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var error: String?
    @State private var child: ChannelRoute?
    @State private var player: PlayerRoute?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: route.title) { dismiss() }
            ScrollView {
                LazyVStack(spacing: 18) {
                    BoothArtwork(kind: .notebook, height: 140)
                    if items.isEmpty, !loading, error == nil { MessagePanel(title: "Nothing here yet", message: "This channel has no available videos.") }
                    ForEach(items, id: \.stableID) { item in
                        Button { open(item) } label: {
                            HStack(spacing: 16) {
                                MediaCover(url: WebAddress.media(item.coverImage), folder: item.isFolder == true)
                                    .frame(width: 80, height: 94).clipShape(RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(verbatim: item.name ?? L10n.text("Untitled")).font(.booth(.headline)).lineLimit(3)
                                    LocalizedText(item.isFolder == true ? "\(item.childrenFileNum ?? 0) videos" : durationLabel(item.length ?? 0))
                                        .font(.caption.monospacedDigit()).foregroundStyle(MicOnStyle.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Glyph(symbol: item.isFolder == true ? .folder : .play, size: 20)
                            }
                        }.buttonStyle(PressStyle())
                    }
                    if let error { ErrorNote(message: error) }
                    if hasMore { ActionButton(title: error == nil ? "Load more" : "Try again", primary: false, busy: loading) { Task { await load() } } }
                }.padding(22)
            }
        }.miconScreenBackground().foregroundStyle(.white)
            .task { if items.isEmpty { await load() } }
            .sheet(item: $child) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
    }
    private func load() async {
        guard !loading, hasMore else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await api.channelPage(link: route.link, page: page)
            var seen = Set(items.map(\.stableID))
            items += result.list.filter { $0.name?.nilIfBlank != nil && !$0.stableID.isEmpty && seen.insert($0.stableID).inserted }
            hasMore = page * 20 < result.total && !result.list.isEmpty
            page += 1
        } catch { self.error = error.localizedDescription }
    }
    private func open(_ item: RemoteLessonFile) {
        if item.isFolder == true, let link = item.landingPage?.nilIfBlank {
            child = ChannelRoute(link: link, title: item.name ?? "Folder")
        } else if let clip = item.clip(channel: route.title) {
            player = PlayerRoute(clips: items.compactMap { $0.clip(channel: route.title) }, startID: clip.id, continuesRecommendations: true)
        } else { error = "This item does not contain a playable video." }
    }
}

struct LinkGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Open your next lesson") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    BoothArtwork(kind: .lesson, height: 150)
                    FeatureRow(symbol: .link, title: "1. Copy a MicOn link", detail: "Use a lesson link or code shared through MicOn.")
                    FeatureRow(symbol: .search, title: "2. Paste it above", detail: "Tap Paste or enter the lesson code exactly as received. Codes are case-sensitive.")
                    FeatureRow(symbol: .play, title: "3. Open and watch", detail: "Tap Open lesson to find matching lessons, then swipe to watch.")
                    LocalizedText("No results? Check your input, or ask the sender for a new link.")
                        .font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.miconPage()
            }
        }.miconScreenBackground().foregroundStyle(.white)
    }
}
