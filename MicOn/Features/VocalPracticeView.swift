import SwiftUI

struct VocalPracticeEntry: View {
    let openJournal: () -> Void

    var body: some View {
        Button(action: openJournal) {
            HStack(spacing: 13) {
                Glyph(symbol: .edit, size: 19, tint: MicOnStyle.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    LocalizedText("Singing log").font(.booth(.headline))
                    LocalizedText("Log the song section, key and how each take went.")
                        .font(.booth(.footnote)).foregroundStyle(MicOnStyle.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Glyph(symbol: .back, size: 12, tint: MicOnStyle.accent).rotationEffect(.degrees(180))
            }.padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .foregroundStyle(MicOnStyle.paper)
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle()).accessibilityIdentifier("practice.openJournal")
    }
}

@MainActor
struct VocalPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @StateObject private var journal = VocalPracticeJournal()
    @State private var title = ""
    @State private var note = ""
    @State private var section = VocalSection.intro
    @State private var semitones = 0
    @State private var withBacking = false
    @State private var history = false
    @State private var selectedSession: VocalPracticeSession?
    @State private var showingRemoval = false
    @State private var sharedExport: SharedFile?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StudioCover(artwork: "JournalCover", height: 130...196, ratio: 1.86,
                            backdrop: MicOnStyle.mediaBackground, artworkSaturation: 0.45) {
                    CoverTitle(title: "Singing log", size: 48).padding(.top, 50)
                }
                VStack(alignment: .leading, spacing: 18) {
                    ChoiceStrip(values: ["Practice", "Sessions"], selected: history ? "Sessions" : "Practice") {
                        history = $0 == "Sessions"
                    }
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    if history { sessions }
                    else if let session = journal.activeSession { practice(session) }
                    else { start }
                }.studioPage()
            }
        }.scrollClipDisabled().scrollDismissesKeyboard(.interactively)
            .studioCoverControl { IconButton(symbol: .close, label: "Close") { dismiss() } }
            .miconScreenBackground(MicOnStyle.mediaBackground).foregroundStyle(MicOnStyle.paper)
            .sheet(item: $selectedSession) { session in sessionDetail(session) }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                CoverTitle(title: "New practice session", size: 39, textStyle: .title)
                LocalizedText("Start with a short phrase and note which key feels comfortable.")
                    .font(.booth(.body)).foregroundStyle(MicOnStyle.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            TextField(L10n.text("Song or phrase (optional)", language: AppLanguage.from(locale)), text: $title)
                .submitLabel(.done)
                .font(.booth(.body)).foregroundStyle(MicOnStyle.paper)
                .tint(MicOnStyle.accent)
                .padding(14).frame(minHeight: 48)
                .studioGlass(in: RoundedRectangle(cornerRadius: 14))
            ActionButton(title: "Start practice") {
                if journal.beginSession(title: title) { title = "" }
            }.disabled(!journal.available)
        }
    }

    private func practice(_ session: VocalPracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sessionTitle(session).font(.booth(.title3, display: true))
            LocalizedText("Log the key change you made in your karaoke player. Listen back before marking the take.").font(.booth(.subheadline))
                .foregroundStyle(MicOnStyle.secondary)
            LocalizedText("Song section").font(.booth(.headline))
            ChoiceStrip(values: VocalSection.allCases.map(\.label), selected: section.label) { label in
                if let selection = VocalSection.allCases.first(where: { $0.label == label }) { section = selection }
            }
            LocalizedText("Key adjustment").font(.booth(.headline))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { amountControls }
                VStack(alignment: .leading, spacing: 8) { amountControls }
            }
            Button { withBacking.toggle() } label: {
                LocalizedText(withBacking ? "With backing track" : "Voice only")
            }.buttonStyle(CompactActionStyle())
                .accessibilityAddTraits(withBacking ? .isSelected : [])
            TextField(L10n.text("Take note (optional)", language: AppLanguage.from(locale)), text: $note, axis: .vertical)
                .lineLimit(2...5).miconField()
            LocalizedText("How did that take go?").font(.booth(.headline))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
                ForEach(VocalResult.allCases) { result in
                    ActionButton(title: result.label, primary: result.countsAsSuccess) {
                        if journal.record(result, section: section, semitones: semitones, withBacking: withBacking, note: note) {
                            note = ""
                        }
                    }
                }
            }
            countSummary(session)
            if let last = session.takes.last { takeRow(last) }
            Button { journal.undoLastTake() } label: { LocalizedText("Undo last take") }
                .buttonStyle(CompactActionStyle()).disabled(session.takes.isEmpty)
            ActionButton(title: "Finish session", primary: false) {
                if journal.finishSession() {
                    note = ""
                    history = true
                }
            }.disabled(session.takes.isEmpty)
        }
    }

    @ViewBuilder private var amountControls: some View {
        Button { semitones -= 1 } label: { LocalizedText("Lower") }
            .buttonStyle(CompactActionStyle()).disabled(semitones <= VocalPracticeJournal.amountRange.lowerBound)
        Text(verbatim: semitones.formatted(.number.sign(strategy: .always())) + " st").font(.booth(.headline)).monospacedDigit()
            .frame(minWidth: 54).accessibilityAddTraits(.updatesFrequently)
        Button { semitones += 1 } label: { LocalizedText("Raise") }
            .buttonStyle(CompactActionStyle()).disabled(semitones >= VocalPracticeJournal.amountRange.upperBound)
    }

    @ViewBuilder private var sessions: some View {
        if journal.completedSessions.isEmpty, journal.available {
            StudioEmptyState(title: "No completed sessions",
                             message: "Once you finish a session, its takes and notes appear here.",
                             actionTitle: "Back to practice", symbol: .edit) {
                history = false
            }.accessibilityIdentifier("practice.emptySessions")
        }
        ForEach(journal.completedSessions) { session in
            Button { selectedSession = session } label: {
                VStack(alignment: .leading, spacing: 8) {
                    sessionTitle(session).font(.booth(.headline))
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute().locale(locale))
                        .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
                    countSummary(session)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background { BoothSurface(tone: .plum) }
                    .contentShape(Rectangle())
            }.buttonStyle(PressStyle())
        }
    }

    private func sessionDetail(_ session: VocalPracticeSession) -> some View {
        VStack(spacing: 0) {
            SheetHeading(title: "Session results") { selectedSession = nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionTitle(session).font(.booth(.title2, display: true))
                    countSummary(session)
                    ForEach(session.takes) { take in takeRow(take) }
                    if let message = journal.storageMessage { ErrorNote(message: message) }
                    ActionButton(title: "Export session CSV", primary: false) {
                        if let url = journal.exportSession(session) { sharedExport = SharedFile(url: url) }
                    }
                    Button { showingRemoval = true } label: { LocalizedText("Delete session") }
                        .buttonStyle(CompactActionStyle())
                }.miconPage()
            }
        }.miconScreenBackground()
            .sheet(item: $sharedExport) { ShareSheet(items: [$0.url]) }
            .fullScreenCover(isPresented: $showingRemoval) {
                AccountDecisionDialog(title: "Delete session?", message: "This deletes the session, including its takes and notes.",
                    confirmTitle: "Delete session", destructive: true, cancel: { showingRemoval = false }) {
                        showingRemoval = false
                        if journal.removeSession(session.id) { selectedSession = nil }
                    }.presentationBackground(.clear)
            }
    }

    @ViewBuilder private func sessionTitle(_ session: VocalPracticeSession) -> some View {
        if let title = session.title.nilIfBlank { Text(verbatim: title) }
        else { LocalizedText("Untitled song") }
    }

    private func countSummary(_ session: VocalPracticeSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(session.successfulTakes) / \(session.takes.count)").font(.booth(.headline)).monospacedDigit()
            LocalizedText("Comfortable takes").font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func takeRow(_ take: VocalTake) -> some View {
        let semitones = take.semitones
        return VStack(alignment: .leading, spacing: 6) {
            LocalizedText(take.section.label).font(.booth(.headline))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: semitones.formatted(.number.sign(strategy: .always())) + " st").monospacedDigit()
                LocalizedText(take.result.label)
            }.font(.booth(.subheadline)).foregroundStyle(MicOnStyle.accent)
            LocalizedText(take.withBacking ? "With backing track" : "Voice only")
                .font(.booth(.caption)).foregroundStyle(MicOnStyle.secondary)
            if !take.note.isEmpty { Text(verbatim: take.note).font(.booth(.subheadline)) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background { BoothSurface(tone: .plum) }
    }
}
