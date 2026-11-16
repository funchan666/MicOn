import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

struct VideoImportControls<Content: View>: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var showingFiles: Bool
    let onImport: (PracticeRecording) -> Void
    var fileActionTitle = "Open video file"
    var onChooseSource: () -> Void = {}
    @ViewBuilder var content: () -> Content
    @State private var showingPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = library.loadError {
                ErrorNote(message: message)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { sourceButtons }
                    VStack(alignment: .leading, spacing: 8) { sourceButtons }
                }
                .disabled(importing)
            }
            if importing {
                LocalizedText("Importing…")
                    .font(.booth(.footnote))
                    .foregroundStyle(MicOnStyle.secondary)
            }
            if let importError { ErrorNote(message: importError) }
            content().disabled(importing)
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let files):
                guard let file = files.first else { return }
                performImport { try await library.importMovie(file) }
            case .failure(let error):
                showImportError(error)
            }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photo, matching: .videos, photoLibrary: .shared())
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            performImport {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                    throw MicOnError.unsupportedMedia
                }
                return try await library.importMovie(movie)
            }
        }
    }

    @ViewBuilder private var sourceButtons: some View {
        Button {
            onChooseSource()
            showingFiles = true
        } label: {
            HStack(spacing: 8) {
                Glyph(symbol: .folder, size: 16, tint: MicOnStyle.ink)
                LocalizedText(fileActionTitle)
                    .font(.booth(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 48)
            .foregroundStyle(MicOnStyle.ink)
            .background(MicOnStyle.accent, in: Capsule())
            .contentShape(.interaction, Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("video.importFiles")

        Button {
            onChooseSource()
            showingPhotos = true
        } label: {
            LocalizedText("Choose from Photos")
                .font(.booth(.subheadline, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(minHeight: 48)
                .foregroundStyle(MicOnStyle.paper)
                .studioGlass(in: Capsule())
                .contentShape(.interaction, Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("video.importPhotos")
    }

    private func performImport(_ operation: @escaping @MainActor () async throws -> PracticeRecording) {
        guard !importing else { return }
        importing = true
        importError = nil
        Task {
            defer { importing = false }
            do { onImport(try await operation()) }
            catch { showImportError(error) }
        }
    }

    private func showImportError(_ error: Error) {
        let failure = error as NSError
        let cancelled = error is CancellationError
            || (failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError)
            || (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled)
        guard !cancelled else { return }
        if failure.domain == NSCocoaErrorDomain,
           [NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError].contains(failure.code) {
            importError = "This file is unavailable. Open the original again or download a new copy."
        } else {
            importError = error.localizedDescription
        }
    }
}

@MainActor
struct VideoFileThumbnail: View {
    let url: URL
    var cover: URL? = nil
    var symbol: MicOnGlyph = .feed
    @State private var frame: UIImage?
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 100
        return cache
    }()

    var body: some View {
        MicOnStyle.mediaSurface
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    Group {
                        if let frame {
                            Image(uiImage: frame).resizable().scaledToFill()
                        } else if let cover {
                            MediaCover(url: cover)
                        } else {
                            Glyph(symbol: symbol, size: 18, tint: MicOnStyle.secondary)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: url) {
                frame = Self.cache.object(forKey: url as NSURL)
                guard frame == nil, url.isFileURL, symbol != .sound else { return }
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 240, height: 240)
                let duration = try? await asset.load(.duration).seconds
                let seconds = duration.flatMap { $0.isFinite && $0 > 0 ? min($0 * 0.12, 3) : nil } ?? 0
                guard !Task.isCancelled,
                      let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)),
                      !Task.isCancelled else { return }
                let image = UIImage(cgImage: result.image)
                Self.cache.setObject(image, forKey: url as NSURL)
                frame = image
            }
    }
}

struct LocalVideoPreview: View {
    let movie: PracticeRecording
    @ObservedObject var playback: PlaybackController
    var canResume: Bool = true
    var chooseFile: (() -> Void)? = nil
    var edit: ((VideoTool) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    @State private var scrubbing = false

    var body: some View {
        let source = library.url(for: movie)
        let loaded = playback.loadedURL == source
        return VStack(alignment: .leading, spacing: 0) {
            VideoStage(playback: playback)
                .overlay {
                    if playback.isLoading {
                        LocalizedText("Preparing preview…")
                            .font(.booth(.footnote, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .studioGlass(in: Capsule())
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: movie.displayName)
                    .font(.booth(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center, spacing: 8) {
                    IconButton(symbol: playback.intendsPlayback ? .pause : .play,
                               label: playback.error != nil ? "Retry" : playback.intendsPlayback ? "Pause" : "Play video") {
                        if playback.error != nil { playback.load(source, autoplay: true) }
                        else { playback.toggle() }
                    }
                    .disabled(scrubbing || !canResume || !loaded)
                    .studioGlass(in: Circle())
                    PlayerProgressControl(playback: playback, timeline: playback.timeline,
                                          enabled: !playback.isLoading && canResume && loaded,
                                          canResume: canResume && scenePhase == .active,
                                          scrubbing: $scrubbing, showsTime: true)
                }
                if let error = playback.error {
                    ErrorNote(message: error)
                    if let chooseFile {
                        ActionButton(title: "Choose another video", primary: false, action: chooseFile)
                            .disabled(!canResume)
                    }
                }
                if let edit, playback.error == nil {
                    VideoToolStrip { tool in
                        playback.pause()
                        edit(tool)
                    }
                    .padding(.top, 6)
                    .disabled(scrubbing || !canResume || !loaded)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .studioGlass(in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("video.preview")
    }
}

private struct VideoStage: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let size = playback.presentationSize
        let ratio = size.width > 0 && size.height > 0 ? size.width / size.height : 16.0 / 9.0
        Color.black
            .aspectRatio(max(0.8, min(ratio, 2.35)), contentMode: .fit)
            .frame(maxHeight: verticalSizeClass == .compact ? 220 : 420)
            .frame(maxWidth: .infinity)
            .background(.black)
            .overlay { VideoSurface(player: playback.player, fill: false) }
            .accessibilityHidden(true)
    }
}

struct LocalVideoSheet: View {
    let movie: PracticeRecording
    let edit: (VideoTool) -> Void
    @StateObject private var playback = PlaybackController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var ads: RewardedAds

    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Play video") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LocalVideoPreview(movie: movie, playback: playback,
                                      canResume: scenePhase == .active && !ads.isPresenting, edit: edit)
                    if playback.error != nil {
                        ActionButton(title: "Back to files", primary: false) { dismiss() }
                    }
                }.miconPage()
            }
        }
        .miconScreenBackground(MicOnStyle.mediaBackground)
        .task {
            guard playback.loadedURL == nil else { playback.pause(); return }
            playback.load(library.url(for: movie), autoplay: scenePhase == .active && !ads.isPresenting)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.pause() }
        }
        .onChange(of: ads.isPresenting) { _, presenting in
            if presenting { playback.pause() }
        }
        .onDisappear { playback.release() }
    }
}

enum VideoTool: String, Identifiable, CaseIterable {
    case studio, frame, speed, audio, export
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: return "Extract audio"
        case .speed: return "Change speed"
        case .frame: return "Crop, rotate & mirror"
        case .studio: return "Video editor"
        case .export: return "Export video"
        }
    }
    var detail: String {
        switch self {
        case .audio: return "Keep the sound as an M4A file."
        case .speed: return "Slow down or speed up a video."
        case .frame: return "Crop, rotate or mirror a clip."
        case .studio: return "Trim a clip and adjust framing, speed or audio."
        case .export: return "Save a video as MP4."
        }
    }
    var shortTitle: String {
        switch self {
        case .audio: return "Audio"
        case .speed: return "Speed"
        case .frame: return "Crop, rotate & mirror"
        case .studio: return "Trim"
        case .export: return "Export"
        }
    }
    var glyph: MicOnGlyph {
        switch self {
        case .audio: return .sound
        case .speed: return .play
        case .frame: return .feed
        case .studio: return .edit
        case .export: return .download
        }
    }
}

private struct VideoToolStrip: View {
    var selected: VideoTool? = nil
    let select: (VideoTool) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let column: GridItem.Size = typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 110)
        LazyVGrid(columns: [GridItem(column, spacing: 6)], spacing: 6) {
            ForEach(VideoTool.allCases) { tool in
                Button { select(tool) } label: {
                    LocalizedText(tool.shortTitle)
                        .font(.booth(.footnote, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected == tool ? MicOnStyle.ink : MicOnStyle.paper)
                        .background(selected == tool ? MicOnStyle.accent : MicOnStyle.mediaSurface,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(.interaction, Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(selected == tool ? .isSelected : [])
                .accessibilityIdentifier("video.tool.\(tool.rawValue)")
            }
        }
    }
}

struct ToolsView: View {
    let movie: PracticeRecording?
    let open: (PracticeRecording?, VideoTool) -> Void
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MediaTitle(title: "Video tools")
                if let movie {
                    HStack(spacing: 14) {
                        VideoFileThumbnail(url: library.url(for: movie)).frame(width: 104)
                        Text(verbatim: movie.displayName)
                            .font(.booth(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studioGlass(in: RoundedRectangle(cornerRadius: 20))
                    ActionButton(title: "Edit video") { open(movie, .studio) }
                        .accessibilityIdentifier("tools.studio")
                } else {
                    ActionButton(title: "Choose a video") { open(nil, .studio) }
                        .accessibilityIdentifier("tools.studio")
                }
                VStack(spacing: 0) {
                    ForEach([VideoTool.frame, .speed, .audio, .export]) { tool in
                        Divider().overlay(MicOnStyle.line)
                        toolButton(tool)
                    }
                }
            }.miconPage()
        }
        .miconScreenBackground(MicOnStyle.mediaBackground)
    }
    private func toolButton(_ tool: VideoTool) -> some View {
        Button { open(movie, tool) } label: {
            HStack(spacing: 13) {
                Glyph(symbol: tool.glyph, size: 18, tint: MicOnStyle.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText(tool.title).font(.booth(.headline))
                    LocalizedText(tool.detail).font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 12, tint: MicOnStyle.accent).rotationEffect(.degrees(180))
            }.padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .foregroundStyle(MicOnStyle.paper)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("tools.\(tool.rawValue)")
    }
}

struct EditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialMovie: PracticeRecording? = nil
    var initialTool: VideoTool = .studio
    var onOpenVideo: (PracticeRecording) -> Void = { _ in }
    @StateObject private var departure = ExportDeparture()
    var body: some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Video editor") { departure.request { dismiss() } }
            EditorWorkspace(initialMovie: initialMovie, initialTool: initialTool, onOpenVideo: onOpenVideo)
        }.miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(MicOnStyle.paper)
            .environmentObject(departure)
            .modifier(ExportDepartureProtection(departure: departure))
    }
}
struct EditorWorkspace: View {
    @EnvironmentObject private var commerce: CommerceStore
    @State private var showingExportMembership = false
    @EnvironmentObject private var departure: ExportDeparture
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var ads: RewardedAds
    let onOpenVideo: (PracticeRecording) -> Void
    @StateObject private var editor = VideoEditor()
    @State private var selected: PracticeRecording?
    @State private var error: String?
    @State private var playbackError: String?
    @State private var shareURL: SharedFile?
    @State private var tool: VideoTool
    @State private var showingFiles = false
    @State private var scrubbing = false
    @State private var savedExport: PracticeRecording?
    @State private var preparingShare = false
    @State private var exportTask: Task<Void, Never>?
    init(initialMovie: PracticeRecording?, initialTool: VideoTool, onOpenVideo: @escaping (PracticeRecording) -> Void) {
        self.onOpenVideo = onOpenVideo
        _selected = State(initialValue: initialMovie)
        _tool = State(initialValue: initialTool)
    }
    private var processing: Bool {
        departure.running || editor.isExporting || editor.isLoading || editor.isPreparingPreview || preparingShare
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let selected {
                    VStack(alignment: .leading, spacing: 24) { editingContent(selected) }
                        .miconPage()
                } else {
                    importContent.miconPage()
                }
            }
        }.miconScreenBackground(MicOnStyle.mediaBackground)
            .onReceive(editor.preview.$error) { playbackError = $0 }
            .sheet(item: $shareURL) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showingExportMembership) { MembershipView(exportRequired: true) }
            .task(id: selected?.id) {
                guard let selected else { return }
                library.recordOpened(selected.id)
                onOpenVideo(selected)
                await editor.open(library.url(for: selected))
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.preview.pause() } }
            .onChange(of: ads.isPresenting) { _, presenting in if presenting { editor.preview.pause() } }
            .onChange(of: editor.recipe) { _, _ in savedExport = nil }
            .onChange(of: tool) { previous, next in
                if previous == .audio || next == .audio { savedExport = nil }
            }
            .onDisappear {
                editor.preview.pause()
                if !showingExportMembership, shareURL == nil {
                    editor.close()
                    exportTask?.cancel()
                }
            }
    }

    private var importContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                MediaTitle(title: "Choose a video")
                LocalizedText(tool.detail)
                    .font(.booth(.subheadline))
                    .foregroundStyle(MicOnStyle.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            VideoImportControls(showingFiles: $showingFiles, onImport: choose) {
                if !library.importedMovies.isEmpty {
                    SectionLabel(title: "Recent imports")
                    ForEach(library.importedMovies) { movie in
                        Button { choose(movie) } label: {
                            HStack(spacing: 14) {
                                VideoFileThumbnail(url: library.url(for: movie)).frame(width: 68)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: movie.displayName).font(.booth(.headline))
                                    LocalizedDateText(date: movie.date).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                                }.fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Glyph(symbol: .edit, size: 18, tint: MicOnStyle.accent)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder private func editingContent(_ selected: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: selected.displayName)
                .font(.booth(.headline))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: clearSelection) {
                LocalizedText(editor.error != nil && editor.duration == 0 ? "Choose another video" : "Change video")
                    .font(.booth(.footnote, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
                    .foregroundStyle(MicOnStyle.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(processing || scrubbing)
        }
        VStack(spacing: 0) {
            VideoStage(playback: editor.preview)
                .overlay {
                    if editor.isLoading || editor.isPreparingPreview {
                        AccountLoadingIndicator(title: editor.isLoading ? "Preparing your video…" : "Preparing preview…")
                    }
                }
            if editor.duration > 0 {
                HStack(spacing: 8) {
                    if let url = editor.preview.loadedURL, playbackError != nil {
                        IconButton(symbol: .play, label: "Retry") { editor.preview.load(url, autoplay: true) }
                            .studioGlass(in: Circle())
                    } else {
                        PreviewButton(playback: editor.preview).disabled(scrubbing)
                    }
                    PlayerProgressControl(playback: editor.preview, timeline: editor.preview.timeline,
                                          enabled: !processing,
                                          canResume: scenePhase == .active && !processing && !ads.isPresenting,
                                          scrubbing: $scrubbing, showsTime: true)
                }
                .padding(10)
                .disabled(processing || ads.isPresenting)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .studioGlass(in: RoundedRectangle(cornerRadius: 20))
        if let error = editor.error { ErrorNote(message: error) }
        if let playbackError {
            ErrorNote(message: playbackError)
        }
        if let error { ErrorNote(message: error) }
        if editor.duration > 0 {
            VideoToolStrip(selected: tool) { tool = $0 }
                .disabled(processing || scrubbing)
            controls.disabled(processing || scrubbing)
            if departure.running {
                VStack(spacing: 14) {
                    LocalizedText(editor.isExporting ? "Exporting · \(Int(editor.progress * 100))%" : "Preparing export…")
                        .font(.booth(.subheadline)).monospacedDigit()
                    ProgressView(value: Double(editor.progress))
                        .tint(MicOnStyle.accent)
                    ActionButton(title: "Cancel export", primary: false) { departure.request() }
                }
            } else {
                outputActions(for: selected)
            }
        }
    }

    private func outputActions(for movie: PracticeRecording) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let savedExport {
                LocalizedText("Saved to Exports")
                    .font(.booth(.subheadline, weight: .semibold))
                    .foregroundStyle(MicOnStyle.accent)
                Text(verbatim: savedExport.displayName)
                    .font(.booth(.footnote))
                    .foregroundStyle(MicOnStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ActionButton(title: "Share", busy: preparingShare) {
                    Task { await share(savedExport) }
                }
            } else {
                ActionButton(title: tool == .audio ? "Export audio as M4A" : "Export video") {
                    export(movie, shareAfterSaving: true)
                }
                ActionButton(title: "Save to Exports", primary: false) {
                    export(movie, shareAfterSaving: false)
                }
            }
            if tool != .audio {
                ActionButton(title: "Preview changes", primary: false) { Task { await editor.applyPreview() } }
            }
        }
        .disabled(processing || scrubbing)
    }

    @ViewBuilder private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch tool {
            case .studio:
                LocalizedText("Trim video").font(.booth(.title3, weight: .bold))
                if !editor.thumbnails.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(editor.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 64).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 10))
                }
                HStack { LocalizedText("Start"); Spacer(); Text(verbatim: durationLabel(editor.recipe.start)).monospacedDigit() }
                MicOnScrubber(value: Binding(get: { editor.recipe.start }, set: { editor.recipe.start = min($0, editor.recipe.end - 0.1); editor.preview.seek($0) }), range: 0...max(0.1, editor.duration), label: "Trim start")
                HStack { LocalizedText("End"); Spacer(); Text(verbatim: durationLabel(editor.recipe.end)).monospacedDigit() }
                MicOnScrubber(value: Binding(get: { editor.recipe.end }, set: { editor.recipe.end = max($0, editor.recipe.start + 0.1) }), range: 0...max(0.1, editor.duration), label: "Trim end")
                LocalizedText("Final duration · \(durationLabel((editor.recipe.end - editor.recipe.start) / editor.recipe.speed))").font(.booth(.footnote)).foregroundStyle(MicOnStyle.accent)
            case .frame:
                LocalizedText("Framing").font(.booth(.title3, weight: .bold))
                FlowChoices(values: VideoFrame.allCases.map(\.rawValue), selected: editor.recipe.frame.rawValue) { value in editor.recipe.frame = VideoFrame(rawValue: value) ?? .original }
                ActionButton(title: "Rotate 90° · \((editor.recipe.quarterTurns % 4) * 90)°", primary: false) { editor.recipe.quarterTurns = (editor.recipe.quarterTurns + 1) % 4 }
                ActionButton(title: editor.recipe.mirrored ? "Mirror: On" : "Mirror: Off", primary: false) { editor.recipe.mirrored.toggle() }
                LocalizedText("Frames crop from the center. Use Preview changes to inspect the result.").font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
            case .speed:
                LocalizedText("Playback speed").font(.booth(.title3, weight: .bold))
                FlowChoices(values: ["0.5×", "0.75×", "1×", "1.5×", "2×"], selected: String(format: "%g×", editor.recipe.speed)) { value in editor.recipe.speed = Double(value.replacingOccurrences(of: "×", with: "")) ?? 1 }
            case .audio:
                LocalizedText("Extract audio").font(.booth(.title3, weight: .bold))
                LocalizedText("Audio extraction uses your trim and speed settings.")
                    .font(.booth(.subheadline)).foregroundStyle(MicOnStyle.secondary)
            case .export:
                LocalizedText("Export settings").font(.booth(.title3, weight: .bold))
                FlowChoices(values: ExportQuality.allCases.map(\.rawValue), selected: editor.recipe.quality.rawValue) { value in editor.recipe.quality = ExportQuality(rawValue: value) ?? .full }
                ActionButton(title: editor.recipe.muted ? "Audio: Muted" : "Audio: Original", primary: false) {
                    editor.recipe.muted.toggle()
                }
                LocalizedText("MP4 · Up to the selected resolution · 30 fps\nSmaller resolutions reduce export size. Source videos are never upscaled.").font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
            }
        }.padding(18).background(MicOnStyle.mediaSurface, in: RoundedRectangle(cornerRadius: 20))
    }
    private func choose(_ movie: PracticeRecording) {
        selected = movie
        error = nil
        savedExport = nil
    }
    private func clearSelection() {
        editor.close()
        selected = nil
        savedExport = nil
        error = nil
        scrubbing = false
    }

    private func export(_ movie: PracticeRecording, shareAfterSaving: Bool) {
        guard exportTask == nil, !processing, editor.duration > 0 else { return }
        editor.preview.pause()
        guard commerce.canExportMedia, let owner = commerce.api.session?.userId.value else {
            showingExportMembership = true
            return
        }
        let audio = tool == .audio
        error = nil
        exportTask = Task {
            defer { exportTask = nil; departure.finish() }
            guard let output = await editor.export(audioOnly: audio) else { return }
            defer { try? FileManager.default.removeItem(at: output) }
            do {
                try Task.checkCancellation()
                let base = (movie.displayName as NSString).deletingPathExtension
                let title = base + (audio ? " · Audio" : " · Edit")
                let saved = try await library.importMovie(output, exported: true, title: title) {
                    try commerce.requireMediaExport()
                    guard commerce.api.session?.userId.value == owner else { throw MicOnError.unauthorized }
                }
                savedExport = saved
                if shareAfterSaving { await share(saved) }
            } catch is CancellationError { }
            catch { self.error = "The export finished but could not be added to your library. \(error.localizedDescription)" }
        }
        departure.begin { exportTask?.cancel(); editor.cancelExport() }
    }

    private func share(_ movie: PracticeRecording) async {
        guard !preparingShare else { return }
        guard commerce.canExportMedia else { showingExportMembership = true; return }
        preparingShare = true
        error = nil
        defer { preparingShare = false }
        do {
            shareURL = SharedFile(url: try await library.shareFile(for: movie, commerce: commerce))
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
struct PreviewButton: View {
    @ObservedObject var playback: PlaybackController
    var body: some View {
        IconButton(symbol: playback.intendsPlayback ? .pause : .play,
                   label: playback.intendsPlayback ? "Pause preview" : "Play preview") { playback.toggle() }
            .studioGlass(in: Circle())
    }
}
struct FlowChoices: View {
    let values: [String]
    let selected: String
    var action: (String) -> Void
    var body: some View {
        ChoiceStrip(values: values, selected: selected, select: action)
    }
}
struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
