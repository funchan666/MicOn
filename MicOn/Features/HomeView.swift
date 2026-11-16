import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var commerce: CommerceStore
    @EnvironmentObject private var quota: QuotaStore
    var discover: () -> Void
    var editVideo: (PracticeRecording, VideoTool) -> Void
    var pausePlayback: Bool
    @Binding var selectedVideoID: String?
    @Binding var link: String
    @State private var searchRequest: LessonSearch?
    @State private var showingCollections = false
    @State private var showingLinkGuide = false
    @State private var showingGuide = false
    @State private var showingJournal = false
    @State private var showingMore = false
    @State private var showingFiles = false
    @State private var previewRequest = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var playback = PlaybackController()
    @State private var openLessonFeedAfterDismissal = false
    @State private var showingLink = false
    @State private var pendingLinkSearch: LessonSearch?
    @State private var composerError: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    videoCover
                    VStack(alignment: .leading, spacing: 28) {
                        VideoImportControls(showingFiles: $showingFiles, onImport: { selectVideo($0) },
                                            onChooseSource: { playback.pause() }) {
                            if selectedVideo == nil, library.importedMovies.isEmpty, library.loadError == nil {
                                LocalizedText("No imported videos yet")
                                    .font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        recentVideos
                        if let movie = selectedVideo {
                            LocalVideoPreview(movie: movie, playback: playback,
                                              canResume: !pausePlayback && scenePhase == .active,
                                              chooseFile: { showingFiles = true }, edit: { tool in
                                editVideo(movie, tool)
                            })
                            .id(movie.id)
                        }
                        secondaryActions
                    }.miconPage(topPadding: 4)
                }
            }
            .scrollClipDisabled(selectedVideo == nil)
            .onChange(of: previewRequest) { _, _ in
                if !pausePlayback, let video = selectedVideo {
                    scroll.scrollTo(video.id, anchor: .top)
                }
            }
        }
            .miconScreenBackground(MicOnStyle.mediaBackground)
            .sheet(isPresented: $showingLink, onDismiss: openPendingLesson) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Open link") { showingLink = false }
                        VStack(alignment: .leading, spacing: 12) {
                            lessonMixer
                            if let composerError { ErrorNote(message: composerError) }
                            if api.session == nil { ConnectionPanel() }
                            recentLinks
                        }.miconPage(topPadding: 0)
                    }
                }.scrollDismissesKeyboard(.interactively)
                    .miconScreenBackground(MicOnStyle.mediaBackground)
                    .dismissKeyboardOnOutsideTap($focused, scope: "home-link-input")
                    .sheet(isPresented: $showingLinkGuide) { LinkGuideSheet() }
            }
            .sheet(isPresented: $showingCollections) { LessonCollectionsSheet() }
            .fullScreenCover(item: $searchRequest) { request in
                DiscoverView(initialSearch: request.query, canDismiss: true) { query, clip in
                    library.record(link: query, title: clip.title)
                }
            }
            .sheet(isPresented: $showingJournal) { VocalPracticeView() }
            .sheet(isPresented: $showingGuide) { VocalGuideView() }
            .task(id: selectedVideo?.id) {
                if let movie = selectedVideo {
                    playback.prepare(library.url(for: movie))
                } else {
                    playback.release()
                }
            }
            .onDisappear { playback.pause() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { playback.pause() }
            }
            .onChange(of: pausePlayback, initial: true) { _, pause in
                if pause { playback.pause() }
            }
    }

    @ViewBuilder private var videoCover: some View {
        if selectedVideo == nil, library.importedMovies.isEmpty, library.loadError == nil {
            StudioCover(artwork: "VideoFilesCover", height: 118...190, ratio: 1.86,
                        backdrop: MicOnStyle.mediaBackground, mirrorsArtworkInRTL: true) {
                MediaTitle(title: "Video files")
            }
        } else {
            MediaTitle(title: "Video files")
                .frame(maxWidth: .infinity, alignment: .leading)
                .miconPage(topPadding: 14)
        }
    }

    private var selectedVideo: PracticeRecording? {
        library.video(withID: selectedVideoID) ?? library.recentlyOpenedVideos.first
    }

    private func selectVideo(_ movie: PracticeRecording, play: Bool = false) {
        let url = library.url(for: movie)
        let autoplay = play && scenePhase == .active && !pausePlayback
        if playback.error != nil || autoplay && playback.loadedURL != url {
            playback.load(url, autoplay: autoplay)
        } else if autoplay {
            playback.play()
        } else {
            playback.prepare(url)
        }
        library.recordOpened(movie.id)
        selectedVideoID = movie.id.uuidString
        previewRequest = UUID()
    }

    @ViewBuilder private var recentVideos: some View {
        let opened = library.recentlyOpenedVideos
        let movies = (opened.isEmpty ? library.importedMovies : opened).prefix(5)
        if !movies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: opened.isEmpty ? "Recent imports" : "Recently opened")
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(movies) { movie in
                            recentButton(movie) {
                                HStack(spacing: 12) {
                                    VideoFileThumbnail(url: library.url(for: movie)).frame(width: 64)
                                    Text(verbatim: movie.displayName)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(movies) { movie in
                                recentButton(movie) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        VideoFileThumbnail(url: library.url(for: movie))
                                        Text(verbatim: movie.displayName).lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(width: 126, alignment: .leading)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func recentButton<Label: View>(_ movie: PracticeRecording, @ViewBuilder label: () -> Label) -> some View {
        let selected = movie.id == selectedVideo?.id
        return Button { selectVideo(movie, play: true) } label: {
            label()
                .font(.booth(.subheadline, weight: .semibold))
                .foregroundStyle(selected ? MicOnStyle.accent : MicOnStyle.paper)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(Text(verbatim: movie.displayName))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var secondaryActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(MicOnStyle.line)
            homeRow(.link, "Open link or code") { showingLink = true }
                .accessibilityIdentifier("home.showLink")
            Button { showingMore.toggle() } label: {
                HStack(spacing: 12) {
                    LocalizedText("Lessons & practice").font(.booth(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Glyph(symbol: .back, size: 12, tint: MicOnStyle.secondary)
                        .rotationEffect(.degrees(showingMore ? expandedAngle : 180))
                }
                .foregroundStyle(MicOnStyle.secondary)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityValue(Text(verbatim: L10n.text(showingMore ? "Expanded" : "Collapsed",
                                                         language: AppLanguage.from(locale))))
            if showingMore {
                VStack(spacing: 0) {
                    homeRow(.feed, "Browse lessons", action: discover)
                    homeRow(.folder, "Lesson collections") { showingCollections = true }
                    homeRow(.edit, "Singing log") { showingJournal = true }
                        .accessibilityIdentifier("practice.openJournal")
                    homeRow(.library, "Karaoke guide") { showingGuide = true }
                        .accessibilityIdentifier("vocalGuide.open")
                }
                .padding(.leading, 12)
            }
        }
    }

    private var expandedAngle: Double { direction == .rightToLeft ? 90 : -90 }

    private func homeRow(_ symbol: MicOnGlyph, _ title: String, action: @escaping () -> Void) -> some View {
        Button {
            playback.pause()
            action()
        } label: {
            HStack(spacing: 12) {
                Glyph(symbol: symbol, size: 16, tint: MicOnStyle.secondary)
                LocalizedText(title).font(.booth(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 12, tint: MicOnStyle.secondary)
                    .rotationEffect(.degrees(180))
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }.buttonStyle(PressStyle())
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
            LocalizedText("Link help").font(.booth(.footnote, weight: .semibold))
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
            LocalizedText("Browse lessons").font(.booth(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .underline().foregroundStyle(MicOnStyle.accent)
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
    }

    private var playLesson: some View {
        Button(action: resolve) {
            HStack(spacing: 10) {
                Glyph(symbol: .play, size: 16, tint: MicOnStyle.ink)
                LocalizedText("Find lessons").font(.booth(.headline, display: true))
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
            TextField(L10n.text("Lesson link or code", language: AppLanguage.from(locale)), text: $link, axis: .vertical)
                .lineLimit(1...3).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($focused).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.paper)
                .tint(MicOnStyle.paper)
                .padding(.leading, 14).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
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
                    .accessibilityLabel(Text(verbatim: L10n.text("Clear link or code", language: AppLanguage.from(locale))))
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
            LocalizedText("Paste link").font(.booth(.footnote, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
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
            composerError = "Copy a lesson link or code, then tap Paste."
            return
        }
        composerError = nil
        link = text
    }
    @ViewBuilder private var recentLinks: some View {
        if !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    LocalizedText("Lesson history").font(.booth(.headline))
                    Spacer()
                    Button { library.clearHistory() } label: { LocalizedText("Clear") }
                        .buttonStyle(MatteActionStyle())
                        .accessibilityLabel(Text(verbatim: L10n.text("Clear history", language: AppLanguage.from(locale))))
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
        playback.pause()
        focused = false
        guard api.session != nil else {
            composerError = "Try again once MicOn connects."
            return
        }
        // Preserve exactly what was entered. Search owns loading, errors and cursor
        // pagination; do not fall back to the old landing-page resolver.
        pendingLinkSearch = LessonSearch(query: text)
        showingLink = false
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
    let owner: String?
    let links: [String]
    let attempt: Int
}

private struct LessonCollectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var commerce: CommerceStore
    @State private var channels: [LandingInfo] = []
    @State private var selectedChannel: ChannelRoute?
    @State private var attempt = 0
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        let request = ChannelRequest(owner: api.session?.userId.value,
                                     links: commerce.release?.lcList?["us"] ?? [], attempt: attempt)
        VStack(spacing: 0) {
            SheetHeading(title: "Lesson collections") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if api.session == nil {
                        ConnectionPanel()
                    } else if loading {
                        AccountLoadingIndicator(title: "Loading…")
                    } else if let error {
                        MessagePanel(title: "Couldn’t load lesson collections", message: error,
                                     actionTitle: "Try again") { attempt += 1 }
                    } else if channels.isEmpty {
                        LocalizedText("No lesson collections yet")
                            .font(.booth(.subheadline))
                            .foregroundStyle(MicOnStyle.secondary)
                    } else {
                        ForEach(channels.indices, id: \.self) { index in
                            if let info = channels[index].extraInfo,
                               let title = info.channelName, let link = info.externalLinks {
                                Button { selectedChannel = ChannelRoute(link: link, title: title) } label: {
                                    HStack(spacing: 12) {
                                        Glyph(symbol: .folder, size: 18, tint: MicOnStyle.secondary)
                                        Text(verbatim: title).font(.booth(.subheadline, weight: .semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Glyph(symbol: .back, size: 12, tint: MicOnStyle.secondary)
                                            .rotationEffect(.degrees(180))
                                    }
                                    .frame(minHeight: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle())
                                Divider().overlay(MicOnStyle.line)
                            }
                        }
                    }
                }.miconPage()
            }
        }
        .miconScreenBackground(MicOnStyle.mediaBackground)
        .sheet(item: $selectedChannel) { ChannelView(route: $0) }
        .task(id: request) {
            loading = true
            error = nil
            channels = []
            guard !request.links.isEmpty, request.owner != nil else { loading = false; return }
            do {
                let results = try await api.channels(links: request.links)
                guard !Task.isCancelled else { return }
                channels = results.filter { $0.extraInfo?.channelName?.nilIfBlank != nil &&
                    $0.extraInfo?.externalLinks?.nilIfBlank != nil }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
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
                VStack(spacing: 18) {
                    if items.isEmpty, !hasMore, !loading, error == nil {
                        StudioCover(artwork: "DiscoverCover", height: 188...294, ratio: 1.42) {
                            CoverTitle(title: "No lessons yet", size: 49)
                        }
                    } else {
                        LazyVStack(spacing: 18) {
                            ForEach(items, id: \.stableID) { item in
                                channelItem(item)
                            }
                            if let error { ErrorNote(message: error) }
                            if hasMore {
                                ActionButton(title: error == nil ? "Load more" : "Try again", primary: false, busy: loading) {
                                    Task { await load() }
                                }
                            }
                        }.padding(22)
                    }
                }
            }.scrollClipDisabled()
        }.miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(.white)
            .task { if items.isEmpty { await load() } }
            .sheet(item: $child) { ChannelView(route: $0) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
    }

    private func channelItem(_ item: RemoteLessonFile) -> some View {
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
    @Environment(\.locale) private var locale

    var body: some View {
        let language = AppLanguage.from(locale)
        VStack(spacing: 0) {
            SheetHeading(title: "Using a link or code") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    FeatureRow(symbol: .link, title: "1. Get a lesson link or code",
                               detail: "Ask the person sharing the lesson to send you its link or code.")
                    FeatureRow(symbol: .search, title: "2. Enter the link or code",
                               detail: "Paste what you received, or type the code with the same capitalization.")
                    FeatureRow(symbol: .play, title: "3. Watch a lesson",
                               detail: L10n.format("Tap %@, then swipe through the results.",
                                                  [L10n.text("Find lessons", language: language)], language: language))
                    LocalizedText("No matches? Check the link or code, or ask the sender for a new one.")
                        .font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                    ActionButton(title: "Got it") { dismiss() }
                }.miconPage()
            }
        }.miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(.white)
    }
}
