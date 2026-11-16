import SwiftUI
import AVFoundation

struct LibraryView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingExportMembership = false
    var edit: (PracticeRecording?, VideoTool) -> Void
    var discover: () -> Void
    var onOpenVideo: (PracticeRecording) -> Void
    @Binding var filter: String
    @State private var showingFiles = false
    @State private var player: PlayerRoute?
    @State private var playingMovie: PracticeRecording?
    @State private var pendingEdit: (movie: PracticeRecording, tool: VideoTool)?
    @State private var sharing: SharedFile?
    @State private var removing: PracticeRecording?
    @State private var removingDownload: OfflineVideo?
    @State private var sharingMovieID: UUID?
    @Environment(\.locale) private var locale

    private var category: Category { Category(rawValue: filter) ?? .imports }
    private var localMovies: [PracticeRecording] {
        library.movies.filter { $0.isExport == (category == .exports) }
    }

    private enum Category: String {
        case imports = "Imports"
        case exports = "Exports"
        case saved = "Saved"
        case offline = "Downloads"

        var glyph: MicOnGlyph {
            switch self {
            case .saved: .bookmark
            case .offline: .download
            case .imports: .folder
            case .exports: .edit
            }
        }
    }

    var body: some View {
        let total = count(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MediaTitle(title: "Files")
                libraryTabs
                librarySection(total: total)
            }.miconPage()
        }
            .miconScreenBackground(MicOnStyle.mediaBackground)
            .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .fullScreenCover(item: $player) { PlayerScreen(route: $0) }
            .sheet(item: $playingMovie, onDismiss: openPendingEdit) { movie in
                LocalVideoSheet(movie: movie) { tool in
                    pendingEdit = (movie, tool)
                    playingMovie = nil
                }
            }
            .sheet(item: $removingDownload) { video in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SheetHeading(title: "Remove download?") { removingDownload = nil }
                        Text(verbatim: video.displayName).font(.booth(.headline)).fixedSize(horizontal: false, vertical: true)
                        LocalizedText("This removes the downloaded copy. The lesson stays in Favorites if you saved it there.")
                            .foregroundStyle(MicOnStyle.secondary)
                        ActionButton(title: "Remove download", primary: false) {
                            offline.remove(video); removingDownload = nil
                        }
                        ActionButton(title: "Keep download") { removingDownload = nil }
                    }.padding(24)
                }.miconScreenBackground().presentationDetents([.medium, .large])
            }
            .sheet(item: $removing) { movie in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SheetHeading(title: "Delete local copy?") { removing = nil }
                        Text(verbatim: movie.displayName).font(.booth(.headline))
                        LocalizedText("MicOn deletes its copy. Any original in Photos or Files stays unchanged.").foregroundStyle(MicOnStyle.secondary)
                        ActionButton(title: "Delete local copy") { library.delete(movie); removing = nil }
                        ActionButton(title: "Cancel", primary: false) { removing = nil }
                    }.padding(24)
                }.miconScreenBackground().presentationDetents([.medium, .large])
            }
    }

    private var libraryTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    primaryTab(.imports)
                    primaryTab(.offline)
                    primaryTab(.exports)
                }
                VStack(spacing: 6) {
                    primaryTab(.imports, multiline: true)
                    primaryTab(.offline, multiline: true)
                    primaryTab(.exports, multiline: true)
                }
            }.padding(5).studioGlass(in: RoundedRectangle(cornerRadius: 20))
            favoritesTab
            Divider().overlay(MicOnStyle.line)
        }
    }

    private func primaryTab(_ entry: Category, multiline: Bool = false) -> some View {
        let selected = category == entry
        let ink = selected ? MicOnStyle.ink : MicOnStyle.paper
        return Button { filter = entry.rawValue } label: {
            HStack(spacing: 8) {
                Glyph(symbol: entry.glyph, size: 16, tint: ink)
                LocalizedText(entry.rawValue).font(.booth(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: !multiline, vertical: true)
            }.padding(.horizontal, 11).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(ink)
                .background(selected ? MicOnStyle.accent : Color.clear, in: RoundedRectangle(cornerRadius: 15))
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var favoritesTab: some View {
        let selected = category == .saved
        return Button { filter = Category.saved.rawValue } label: {
            HStack(spacing: 7) {
                Glyph(symbol: .bookmark, size: 15, tint: selected ? MicOnStyle.accent : MicOnStyle.secondary)
                LocalizedText("Favorites").font(.booth(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .underline(selected)
            }.padding(.horizontal, 7).padding(.vertical, 6).frame(minHeight: 44)
                .foregroundStyle(selected ? MicOnStyle.accent : MicOnStyle.paper)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func librarySection(total: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if total > 0 {
                itemCount(total)
            } else if category != .offline, let loadError = library.loadError {
                ErrorNote(message: loadError)
            } else if category == .offline, offline.busy {
                if offline.isRestoring, offline.downloadingID == nil {
                    AccountLoadingIndicator(title: "Loading…")
                } else if offline.preparingID != nil, offline.downloadingID == nil {
                    AccountLoadingIndicator(title: "Preparing download…")
                }
            } else if category == .offline, let error = offline.error {
                StudioEmptyState(title: "Downloads", message: error,
                                 actionTitle: "Browse lessons", symbol: .feed, action: discover)
            } else if category == .offline, api.offlineOwnerID == nil, api.session == nil {
                ConnectionPanel()
            } else {
                emptyLibrary
            }
            if category == .offline { DownloadAllowanceSummary() }
            if category == .offline, total > 0 || offline.busy {
                downloadStatus
            } else if offline.downloadingID != nil {
                Button { filter = Category.offline.rawValue } label: {
                    HStack(spacing: 10) {
                        Glyph(symbol: .download, size: 15, tint: MicOnStyle.accent)
                        LocalizedText("Downloading · \(Int(offline.progress * 100))%")
                            .font(.booth(.footnote, weight: .semibold)).monospacedDigit()
                        Spacer(minLength: 0)
                        Glyph(symbol: .back, size: 12, tint: MicOnStyle.secondary)
                            .rotationEffect(.degrees(180))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }.buttonStyle(PressStyle())
            }
            if total > 0 {
                LazyVStack(spacing: 4) {
                    switch category {
                    case .saved:
                        ForEach(library.favorites) { clip in favoriteRow(clip) }
                    case .offline:
                        ForEach(offline.videos) { video in downloadRow(video) }
                    case .imports, .exports:
                        ForEach(localMovies) { movie in movieRow(movie) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var emptyLibrary: some View {
        switch category {
        case .saved:
            StudioEmptyState(title: "No favorites yet",
                             message: "Favorite a lesson while watching to keep it here.",
                             actionTitle: "Browse lessons", symbol: .feed, primary: true, action: discover)
        case .offline:
            StudioEmptyState(title: "No downloads yet",
                             message: "Use the download button in the player to watch a lesson offline.",
                             actionTitle: "Browse lessons", symbol: .feed, primary: true, action: discover)
        case .imports:
            VStack(alignment: .leading, spacing: 16) {
                MediaTitle(title: "No imported videos yet", textStyle: .title2)
                VideoImportControls(showingFiles: $showingFiles, onImport: playMovie, fileActionTitle: "Import a video") {
                    EmptyView()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioGlass(in: RoundedRectangle(cornerRadius: 20))
        case .exports:
            StudioEmptyState(title: "No exports yet",
                             message: "Export a video or audio track to find it here.",
                             actionTitle: "Choose a video", symbol: .edit, primary: true) { edit(nil, .export) }
        }
    }

    private func itemCount(_ total: Int) -> some View {
        LocalizedText(category == .saved ? "\(total) videos" : "\(total) \(total == 1 ? "item" : "items") · On this device")
            .font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
    }

    private func count(in entry: Category) -> Int {
        switch entry {
        case .saved: library.favorites.count
        case .offline: offline.videos.count
        case .imports: library.movies.lazy.filter { !$0.isExport }.count
        case .exports: library.movies.lazy.filter(\.isExport).count
        }
    }

    @ViewBuilder private var downloadStatus: some View {
        if offline.downloadingID != nil || offline.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                if offline.downloadingID != nil {
                    if let title = offline.currentTitle {
                        Text(verbatim: title).font(.booth(.subheadline, weight: .semibold)).lineLimit(2)
                    }
                    LocalizedText("Downloading · \(Int(offline.progress * 100))%")
                        .font(.booth(.caption)).monospacedDigit()
                    Button("Cancel download") { Task { await offline.cancel() } }
                        .buttonStyle(LibraryActionStyle())
                }
                if let error = offline.error {
                    ErrorNote(message: error)
                    if offline.downloadingID != nil {
                        Button("Retry") { Task { await offline.retryCompletion() } }
                            .buttonStyle(LibraryActionStyle())
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(MicOnStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func favoriteRow(_ clip: LessonClip) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { player = PlayerRoute(clips: library.favorites, startID: clip.id) } label: {
                HStack(spacing: 10) {
                    MediaCover(url: clip.coverURL).frame(width: 44, height: 44)
                        .clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
                    lessonTitle(clip)
                    Glyph(symbol: .play, size: 16, tint: MicOnStyle.ink)
                        .frame(width: 34, height: 34)
                        .background(MicOnStyle.accent, in: Capsule()).accessibilityHidden(true)
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            removeButton(.bookmark, title: "Remove saved video") { library.toggle(clip) }
        }
        .modifier(LibraryRowSurface())
    }


    private func lessonTitle(_ clip: LessonClip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: clip.title).font(.booth(.subheadline, weight: .semibold)).lineLimit(3)
            if !clip.channel.isEmpty {
                Text(verbatim: clip.channel).font(.booth(.caption))
                    .foregroundStyle(MicOnStyle.secondary).lineLimit(2)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func downloadRow(_ video: OfflineVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { playDownload(video) } label: {
                HStack(spacing: 12) {
                    VideoFileThumbnail(url: video.url, cover: video.clip.coverURL, symbol: .download)
                        .frame(width: 74)
                    Text(verbatim: video.displayName)
                        .font(.booth(.subheadline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Glyph(symbol: .play, size: 16, tint: MicOnStyle.ink)
                        .frame(width: 34, height: 34)
                        .background(MicOnStyle.accent, in: Circle())
                }.contentShape(Rectangle())
            }.buttonStyle(PressStyle())
            HStack(spacing: 8) {
                VideoExportEntry(clip: offline.playable(video.clip), compact: true)
                Spacer(minLength: 0)
                removeButton(.close, title: "Remove download") { removingDownload = video }
            }
        }
        .modifier(LibraryRowSurface())
    }

    private func movieRow(_ movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VideoFileThumbnail(url: library.url(for: movie), symbol: movie.isAudio ? .sound : .feed)
                    .frame(width: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: movie.displayName)
                        .font(.booth(.subheadline, weight: .semibold))
                    LocalizedDateText(date: movie.date)
                        .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !movie.isAudio {
                    IconButton(symbol: .play, label: "Play video") { playMovie(movie) }
                        .studioGlass(in: Circle())
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { movieActions(movie) }
                VStack(alignment: .leading, spacing: 6) { movieActions(movie) }
            }
        }
        .modifier(LibraryRowSurface())
    }

    @ViewBuilder private func movieActions(_ movie: PracticeRecording) -> some View {
        if !movie.isAudio {
            Button { edit(movie, .studio) } label: { LocalizedText("Edit") }
                .buttonStyle(LibraryActionStyle())
        }
        Button {
            shareMovie(movie)
        } label: {
            LocalizedText(sharingMovieID == movie.id ? "Preparing export…" : "Share")
        }
        .buttonStyle(LibraryActionStyle())
        .disabled(sharingMovieID != nil)
        removeButton(.close, title: "Delete local file") { removing = movie }
    }

    private func playMovie(_ movie: PracticeRecording) {
        library.recordOpened(movie.id)
        onOpenVideo(movie)
        playingMovie = movie
    }

    private func openPendingEdit() {
        guard let pendingEdit else { return }
        self.pendingEdit = nil
        edit(pendingEdit.movie, pendingEdit.tool)
    }

    private func removeButton(_ symbol: MicOnGlyph, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(symbol: symbol, size: 16, tint: MicOnStyle.accent)
                .frame(width: 36, height: 36)
                .background(MicOnStyle.surface, in: Capsule())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityLabel(LocalizedStringKey(title))
    }

    private func playDownload(_ video: OfflineVideo) {
        let clips = offline.videos.compactMap { item -> LessonClip? in
            offline.cached(item.id) == nil ? nil : offline.playable(item.clip)
        }
        if clips.contains(where: { $0.id == video.id }) {
            player = PlayerRoute(clips: clips, startID: video.id)
        } else { offline.error = "This download is no longer on this device. Download it again." }
    }

    private func shareMovie(_ movie: PracticeRecording) {
        guard commerce.canExportMedia else {
            showingExportMembership = true
            return
        }
        sharingMovieID = movie.id
        Task {
            defer { sharingMovieID = nil }
            do { sharing = SharedFile(url: try await library.shareFile(for: movie, commerce: commerce)) }
            catch { library.error = error.localizedDescription }
        }
    }
}

private struct LibraryRowSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Divider().overlay(MicOnStyle.line).allowsHitTesting(false) }
    }
}

private struct LibraryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.booth(.footnote, weight: .semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(MicOnStyle.paper)
            .background(MicOnStyle.raised, in: Capsule())
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.58 : configuration.isPressed ? 0.72 : 1)
    }
}

// Uses the existing original bitmap action surfaces; no new system artwork.
struct OfflineDownloadButton: View {
    let clip: LessonClip
    var starting = false
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DownloadAllowanceSummary()
            if offline.cached(clip.id) != nil || clip.playbackURL.isFileURL {
                LocalizedText("Available offline").font(.booth(.subheadline)).foregroundStyle(MicOnStyle.accent)
                DownloadCompletionNotice()
            } else if starting || offline.preparingID == clip.id {
                ActionButton(title: "Preparing download…", primary: false, busy: true) { }
                LocalizedText("Preparing download…").font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
            } else if offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.booth(.caption))
                ActionButton(title: "Cancel download", primary: false) { Task { await offline.cancel() } }
            } else {
                ActionButton(title: "Download to watch offline", primary: false) {
                    if quota.mayDownload(clip.id, premium: commerce.premium) {
                        Task { await offline.download(clip) }
                    } else { downloadGate = true }
                }.disabled(offline.busy || clip.playbackURL.isFileURL)
                    .accessibilityIdentifier("player.downloadOffline")
                if offline.isRestoring {
                    LocalizedText("Restoring downloads…").font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                } else if offline.busy {
                    LocalizedText("Another download is in progress.").font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                }
            }
            VideoExportEntry(clip: clip)
            if let error = offline.error {
                ErrorNote(message: error)
                if offline.downloadingID == clip.id {
                    ActionButton(title: "Retry", primary: false) { Task { await offline.retryCompletion() } }
                }
            }
        }.sheet(isPresented: $downloadGate) { MembershipView(rewardKind: .download) }
    }
}

// A separate, always-visible workflow; users need not visit the cache panel.
struct VideoExportEntry: View {
    let clip: LessonClip
    var compact = false
    @State private var showingExport = false
    @EnvironmentObject private var commerce: CommerceStore
    var body: some View {
        Group {
            if compact {
                Button("Export") { showingExport = true }.buttonStyle(LibraryActionStyle())
            } else {
                ActionButton(title: "Export video", primary: false) { showingExport = true }
            }
        }.accessibilityIdentifier("player.openExport")
            .sheet(isPresented: $showingExport) {
                if commerce.canExportMedia { OfflineExportSheet(clip: clip) }
                else { MembershipView(exportRequired: true) }
            }
    }
}

private struct OfflineExportSheet: View {
    let clip: LessonClip
    @Environment(\.dismiss) private var dismiss
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeading(title: "Export video") { departure.request { dismiss() } }
                Text(verbatim: clip.title).font(.booth(.subheadline)).lineLimit(2)
                OfflineExportButton(clip: clip)
            }.padding(22)
        }.miconScreenBackground().presentationDetents([.medium, .large])
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}

// One owner for the close button, explicit cancel and interactive dismissal.
@MainActor
final class ExportDeparture: ObservableObject {
    @Published private(set) var running = false
    @Published var confirming = false
    private var cancellation: (() -> Void)?
    private var afterCancellation: (() -> Void)?
    func begin(cancel: @escaping () -> Void) { running = true; cancellation = cancel }
    func finish() {
        running = false; cancellation = nil
        confirming = false; afterCancellation = nil
    }
    func request(_ close: @escaping () -> Void = {}) {
        guard running else { close(); return }
        afterCancellation = close; confirming = true
    }
    func keepWorking() { confirming = false; afterCancellation = nil }
    func stop() {
        let close = afterCancellation
        cancellation?()
        confirming = false; afterCancellation = nil
        close?()
    }
}

struct ExportDepartureProtection: ViewModifier {
    @ObservedObject var departure: ExportDeparture
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(departure.running)
            .accessibilityHidden(departure.confirming)
            .overlay {
                if departure.confirming {
                    GeometryReader { container in
                        ScrollView {
                            VStack(spacing: 18) {
                                LocalizedText("Stop this export?").font(.booth(.headline))
                                LocalizedText("Your original video stays unchanged.")
                                    .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ActionButton(title: "Keep exporting", action: departure.keepWorking)
                                ActionButton(title: "Stop export", primary: false, action: departure.stop)
                            }.padding(22).frame(maxWidth: 360)
                                .background { BoothSurface(tone: .plum) }.padding(20)
                                .frame(maxWidth: .infinity, minHeight: container.size.height)
                        }.background(.black.opacity(0.7))
                            .accessibilityAddTraits(.isModal)
                    }
                }
            }
    }
}

struct DownloadCompletionNotice: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.locale) private var locale
    var body: some View {
        Group {
            if offline.completedDownloadID != nil {
                HStack(spacing: 12) {
                    LocalizedText("Ready to watch offline")
                        .font(.booth(.caption)).fixedSize(horizontal: false, vertical: true)
                    Button {
                        offline.completedDownloadID = nil
                        library.openDownloads()
                    } label: { LocalizedText("View") }
                        .buttonStyle(CompactActionStyle())
                        .accessibilityLabel(Text(verbatim: L10n.text("View downloads", language: AppLanguage.from(locale))))
                    IconButton(symbol: .close, label: "Dismiss message") { offline.completedDownloadID = nil }
                }.padding(12).foregroundStyle(MicOnStyle.paper)
                    .background { BoothSurface(tone: .plum) }
                    .padding(.horizontal, 12)
            }
        }.task(id: offline.completedDownloadID) {
            guard let notice = offline.completedDownloadID else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            if offline.completedDownloadID == notice { offline.completedDownloadID = nil }
        }
    }
}

// Uncached exports use the same download admission and completion journal.
// Export is a Plus benefit; cached copies still pass the membership check.
private struct OfflineExportButton: View {
    let clip: LessonClip
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var downloadGate = false
    @State private var preparingSource = false
    @State private var exportTask: Task<Void, Never>?
    @State private var sharing: SharedFile?
    @State private var exportError: String?
    @State private var exportedFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(title: preparingSource ? "Preparing export…" : exportTask == nil ? "Export video" : "Exporting…",
                         primary: false, busy: exportTask != nil, action: startExport)
                .accessibilityIdentifier("player.exportVideo")
            if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil {
                LocalizedText("Export uses your saved download when available. Otherwise, MicOn downloads the video first.")
                    .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                DownloadAllowanceSummary()
            }
            if preparingSource, offline.downloadingID == clip.id {
                LocalizedText("Downloading · \(Int(offline.progress * 100))%").font(.booth(.caption))
            }
            if exportTask != nil {
                Button("Cancel export") { departure.request() }.buttonStyle(CompactActionStyle())
            }
            if let exportError { ErrorNote(message: exportError) }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $downloadGate) { MembershipView(exportRequired: true) }
        .onDisappear { exportTask?.cancel() }
    }

    private func startExport() {
        guard exportTask == nil else { return }
        guard commerce.canExportMedia, let owner = commerce.api.session?.userId.value else {
            downloadGate = true
            return
        }
        if !clip.playbackURL.isFileURL, offline.cached(clip.id) == nil,
           !quota.mayDownload(clip.id, premium: commerce.premium) {
            downloadGate = true
            return
        }
        if let exportedFile, FileManager.default.fileExists(atPath: exportedFile.path) {
            sharing = SharedFile(url: exportedFile); return
        }
        exportError = nil
        exportTask = Task { @MainActor in
            defer { exportTask = nil; preparingSource = false; departure.finish() }
            var ownsDownload = false
            var converted: URL?
            defer { if let converted { try? FileManager.default.removeItem(at: converted) } }
            do {
                try commerce.requireMediaExport()
                var source = clip.playbackURL
                if !source.isFileURL || offline.cached(clip.id)?.isHLS == true {
                    preparingSource = true
                    // A cache request may already be finishing for this clip.
                    // Let it finish, then decide whether its result is a file
                    // or whether the original-file download is still needed.
                    if offline.downloadingID == clip.id {
                        for await downloadID in offline.$downloadingID.values {
                            try Task.checkCancellation()
                            if downloadID != clip.id { break }
                        }
                    }
                    try Task.checkCancellation()
                    if offline.cached(clip.id)?.isHLS != false, offline.downloadingID != clip.id {
                        guard !offline.busy else { throw MicOnError.service("Another download is in progress.") }
                        ownsDownload = true
                        await offline.download(clip, forExport: true)
                    }
                    // Subscribe to the shared download state, including its
                    // current value, so a very fast completion is not missed.
                    for await downloadID in offline.$downloadingID.values {
                        try Task.checkCancellation()
                        if let cached = offline.cached(clip.id), !cached.isHLS { source = cached.url; break }
                        guard downloadID == clip.id else {
                            throw MicOnError.service(offline.error ?? "Download failed. No download allowance was used.")
                        }
                    }
                    try Task.checkCancellation()
                    guard source.isFileURL else { throw MicOnError.storage }
                    preparingSource = false
                }
                var output = source
                if !["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) {
                    let asset = AVURLAsset(url: source)
                    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
                          session.supportedFileTypes.contains(.mp4) else {
                        throw MicOnError.service("This video format cannot be exported. Please use an MP4 or MOV file.")
                    }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
                    converted = destination
                    session.outputURL = destination
                    session.outputFileType = .mp4
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { continuation in
                            session.exportAsynchronously { continuation.resume() }
                        }
                    } onCancel: { session.cancelExport() }
                    try Task.checkCancellation()
                    guard session.status == .completed else {
                        throw MicOnError.service("Video export failed. Please try again.")
                    }
                    output = destination
                }
                try Task.checkCancellation()
                let recording = try await library.importMovie(output, exported: true, title: clip.title) {
                    try commerce.requireMediaExport()
                    guard commerce.api.session?.userId.value == owner else { throw MicOnError.unauthorized }
                }
                let url = try await library.shareFile(for: recording, commerce: commerce)
                exportedFile = url
                if !Task.isCancelled { sharing = SharedFile(url: url) }
            } catch is CancellationError {
                if ownsDownload, offline.downloadingID == clip.id { await offline.cancel() }
            }
            catch {
                exportError = error.localizedDescription
            }
        }
        departure.begin { exportTask?.cancel() }
    }
}

// Shared, live allowance display at the download decision and in the offline library.
struct DownloadAllowanceSummary: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var quota: QuotaStore
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingReward = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText("Downloads left").font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
            LocalizedText(api.session == nil ? "Connect to refresh your allowance." :
                            commerce.premium || quota.downloadsUnlimited ? "Unlimited" :
                            quota.usage == nil ? "Loading…" : "\(quota.downloadsLeft) downloads left today")
                .font(.booth(.subheadline, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if quota.usage != nil, !commerce.premium { AllowanceResetText() }
            if quota.canRequestReward(for: .download, premium: commerce.premium) {
                ActionButton(title: "Get more downloads", primary: false) { showingReward = true }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background { BoothSurface(tone: .plum) }
            .accessibilityElement(children: .contain)
            .onAppear { quota.resetIfNeeded() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in quota.resetIfNeeded() }
            .sheet(isPresented: $showingReward) { MembershipView(rewardKind: .download) }
    }
}
