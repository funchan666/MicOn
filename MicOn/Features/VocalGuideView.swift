import SwiftUI

// Bundled, original editorial content. Reading never calls video, quota or advertising APIs.
private struct VocalNote: Identifiable {
    struct Section {
        let title: String
        let body: String
        init(_ title: String, _ body: String) { self.title = title; self.body = body }
    }
    let id: String
    let category: String
    let title: String
    let shortTitle: String
    let summary: String
    let cover: GuideArtwork.Subject
    let sections: [Section]
    let takeaway: String

    static let all: [VocalNote] = [
        VocalNote(
            id: "breath", category: "Warm-up", title: "Warm up at speaking volume", shortTitle: "Warm up at speaking volume",
            summary: "Start gently before tackling a chorus.", cover: .breath,
            sections: [.init("Find an easy note", "Hum a comfortable note for a few seconds, then rest. Keep your jaw relaxed and use a light speaking volume."),
                       .init("Try a short phrase", "Speak a line in rhythm. Then sing it at the same comfortable loudness. Pause if the effort increases.")],
            takeaway: "An easy warm-up should feel repeatable."),
        VocalNote(
            id: "phrase", category: "Song practice", title: "Mark the breathing spots", shortTitle: "Mark the breathing spots",
            summary: "Give each phrase a clear place to start and breathe.", cover: .phrase,
            sections: [.init("Speak it first", "Say the words over the beat and notice where you naturally take air. Mark one spot before each long phrase."),
                       .init("Sing the marked version", "Sing slowly with the planned pauses. If you run out of air, shorten the phrase or move the breathing spot earlier.")],
            takeaway: "A breath can support the rhythm when you plan it."),
        VocalNote(
            id: "distance", category: "Mic technique", title: "Keep a consistent mic distance", shortTitle: "Keep a consistent mic distance",
            summary: "Let the microphone do the work of getting louder.", cover: .distance,
            sections: [.init("Set a starting distance", "Hold a handheld mic a comfortable few centimeters away and sing an easy line. Listen to the room rather than raising your voice."),
                       .init("Compare one adjustment", "Move it slightly farther away for a loud note. Try a slight angle when a consonant produces a hard pop.")],
            takeaway: "Listen back before changing the distance again."),
        VocalNote(
            id: "chorus", category: "Song practice", title: "Find a comfortable chorus key", shortTitle: "Find a comfortable chorus key",
            summary: "Choose a key you can repeat comfortably through the whole song.", cover: .chorus,
            sections: [.init("Try the hardest line", "Sing the chorus line that feels most demanding. If your player can change key, try it one semitone lower and compare."),
                       .init("Check the low notes", "Sing part of the verse in the new key before deciding. Save the setting where both verse and chorus feel manageable.")],
            takeaway: "Keep the key that works for the full song."),
        VocalNote(
            id: "rest", category: "Warm-up", title: "Put a pause between takes", shortTitle: "Put a pause between takes",
            summary: "Short breaks keep repeated practice manageable.", cover: .rest,
            sections: [.init("Choose one target", "Work on one short section per take. Put the microphone down and have a sip of water between repetitions."),
                       .init("Stop if it hurts", "Take a break when your voice feels strained or uncomfortable. Save your notes so you can resume later.")],
            takeaway: "Record the point where the phrase felt easy to repeat."),
        VocalNote(
            id: "listen", category: "Mic technique", title: "Listen back for one thing", shortTitle: "Listen back for one thing",
            summary: "Compare two takes with one clear question in mind.", cover: .listen,
            sections: [.init("Use the same phrase", "Record the same few bars twice and change one choice, such as the breathing spot or microphone distance."),
                       .init("Write what you heard", "Listen to the two takes at the same volume. Note the difference in words, then choose what to repeat.")],
            takeaway: "A short note helps you remember the setup that worked.")
    ]
}

// Shared entry point for Home and the practice tools.
struct VocalGuideEntry: View {
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 13) {
                Glyph(symbol: .library, size: 19, tint: MicOnStyle.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Karaoke guide").font(.booth(.headline))
                        .foregroundStyle(MicOnStyle.paper)
                    LocalizedText("%@ tips available offline", String(VocalNote.all.count))
                        .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 12, tint: MicOnStyle.accent).rotationEffect(.degrees(180))
            }.padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("vocalGuide.open")
    }
}

struct VocalGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var category = "All"
    private let categories = ["All", "Warm-up", "Song practice", "Mic technique"]
    private var notes: [VocalNote] {
        VocalNote.all.filter { category == "All" || $0.category == category }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    StudioCover(artwork: GuideArtwork.Subject.breath.rawValue, height: 134...202, ratio: 1.85,
                                backdrop: MicOnStyle.mediaBackground, artworkSaturation: 0.45) {
                        CoverTitle(title: "Karaoke guide", size: 47).padding(.top, 50)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        ChoiceStrip(values: categories, selected: category) { category = $0 }
                        if let first = notes.first {
                            NavigationLink(value: first.id) {
                                HStack(spacing: 14) {
                                    featuredCopy(first).frame(maxWidth: .infinity, alignment: .leading)
                                    Glyph(symbol: .back, size: 14, tint: MicOnStyle.ink).rotationEffect(.degrees(180))
                                }.padding(18).foregroundStyle(MicOnStyle.ink)
                                    .background { BoothSurface(tone: .blush) }
                                    .contentShape(Rectangle())
                            }.buttonStyle(PressStyle()).accessibilityIdentifier("vocalGuide.\(first.id)")
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 140), spacing: 16)], alignment: .leading, spacing: 22) {
                            ForEach(Array(notes.dropFirst())) { note in
                                NavigationLink(value: note.id) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        GuideArtwork(subject: note.cover)
                                            .aspectRatio(1.65, contentMode: .fit)
                                            .saturation(0.55)
                                        LocalizedText(note.shortTitle).font(.booth(.headline))
                                            .fixedSize(horizontal: false, vertical: true)
                                        LocalizedText(note.summary).font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }.foregroundStyle(MicOnStyle.paper).contentShape(Rectangle())
                                }.buttonStyle(PressStyle()).accessibilityIdentifier("vocalGuide.\(note.id)")
                            }
                        }
                    }.studioPage()
                }
            }.scrollClipDisabled()
                .studioCoverControl { IconButton(symbol: .close, label: "Close") { dismiss() } }
                .miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(MicOnStyle.paper)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    if let note = VocalNote.all.first(where: { $0.id == id }) {
                        VocalNoteReader(note: note)
                    }
                }
        }
    }
    private func featuredCopy(_ note: VocalNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedText(note.category).font(.booth(.caption, weight: .semibold)).foregroundStyle(MicOnStyle.paperSecondary)
            LocalizedText(note.title).font(.booth(.title3, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            LocalizedText(note.summary).font(.booth(.subheadline)).foregroundStyle(MicOnStyle.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VocalNoteReader: View {
    let note: VocalNote
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StudioCover(artwork: note.cover.rawValue, height: 152...224, ratio: 1.68,
                            backdrop: MicOnStyle.mediaBackground, artworkSaturation: 0.45) {
                    VStack(alignment: .leading, spacing: 8) {
                        LocalizedText(note.category).font(.booth(.subheadline, weight: .semibold))
                            .foregroundStyle(MicOnStyle.accent)
                        CoverTitle(title: note.title, size: 49)
                    }.padding(.top, 50)
                }
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(note.sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(verbatim: "\(index + 1)").font(.booth(.subheadline, weight: .black)).monospacedDigit()
                                    .foregroundStyle(MicOnStyle.accent).accessibilityHidden(true)
                                LocalizedText(note.sections[index].title).font(.booth(.headline))
                                    .accessibilityAddTraits(.isHeader)
                            }
                            LocalizedText(note.sections[index].body).font(.booth(.body)).lineSpacing(5)
                                .foregroundStyle(MicOnStyle.paper.opacity(0.9))
                                .textSelection(.enabled)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        LocalizedText("One thing to remember").font(.booth(.caption, weight: .bold))
                        LocalizedText(note.takeaway).font(.booth(.body, weight: .medium)).lineSpacing(3)
                    }.foregroundStyle(MicOnStyle.ink)
                        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background { BoothSurface(tone: .blush) }
                }.studioPage()
            }
        }.scrollClipDisabled()
            .studioCoverControl(alignment: .leading) {
                IconButton(symbol: .back, label: "Back") { dismiss() }
            }
            .miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(MicOnStyle.paper)
            .toolbar(.hidden, for: .navigationBar)
    }
}
