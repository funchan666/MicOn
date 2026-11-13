import Foundation
import Combine

enum VocalSection: String, Codable, CaseIterable, Identifiable {
    case intro, verse, preChorus, chorus, bridge, outro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .intro: "Intro"
        case .verse: "Verse"
        case .preChorus: "Pre-chorus"
        case .chorus: "Chorus"
        case .bridge: "Bridge"
        case .outro: "Outro"
        }
    }
}

enum VocalResult: String, Codable, CaseIterable, Identifiable {
    case comfortable, breathShort, pitchDrift, timingSlip
    var id: String { rawValue }
    var label: String {
        switch self {
        case .comfortable: "Comfortable"
        case .breathShort: "Ran out of breath"
        case .pitchDrift: "Pitch drift"
        case .timingSlip: "Timing slipped"
        }
    }
    var countsAsSuccess: Bool { self == .comfortable }
}

struct VocalTake: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let section: VocalSection
    let semitones: Int
    let withBacking: Bool
    let result: VocalResult
    let note: String
}

struct VocalPracticeSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    let title: String
    var finishedAt: Date?
    var takes: [VocalTake]
    var successfulTakes: Int { takes.filter { $0.result.countsAsSuccess }.count }
}

private struct VocalJournalArchive: Codable {
    var activeSession: VocalPracticeSession?
    var completedSessions: [VocalPracticeSession] = []
}

@MainActor
final class VocalPracticeJournal: ObservableObject {
    static let amountRange = -6...6
    @Published private var archive = VocalJournalArchive()
    @Published private(set) var storageMessage: String?
    private let archiveURL: URL
    private(set) var available = true
    var activeSession: VocalPracticeSession? { archive.activeSession }
    var completedSessions: [VocalPracticeSession] { archive.completedSessions }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VocalPractice", isDirectory: true)
        archiveURL = folder.appendingPathComponent("sessions.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                archive = try JSONDecoder().decode(VocalJournalArchive.self, from: Data(contentsOf: archiveURL))
            }
        } catch {
            available = false
            storageMessage = "Practice records could not be opened. Existing records are preserved."
        }
    }

    @discardableResult
    func beginSession(title: String) -> Bool {
        guard activeSession == nil else { return false }
        var next = archive
        next.activeSession = VocalPracticeSession(id: UUID(), startedAt: Date(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), takes: [])
        return commit(next)
    }

    @discardableResult
    func record(_ result: VocalResult, section: VocalSection, semitones: Int, withBacking: Bool, note: String) -> Bool {
        guard var session = activeSession, Self.amountRange.contains(semitones) else { return false }
        session.takes.append(VocalTake(id: UUID(), recordedAt: Date(), section: section,
            semitones: semitones, withBacking: withBacking, result: result,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        var next = archive
        next.activeSession = session
        return commit(next)
    }

    func undoLastTake() {
        guard var session = activeSession, !session.takes.isEmpty else { return }
        session.takes.removeLast()
        var next = archive
        next.activeSession = session
        commit(next)
    }

    @discardableResult
    func finishSession() -> Bool {
        guard var session = activeSession, !session.takes.isEmpty else { return false }
        session.finishedAt = Date()
        var next = archive
        next.completedSessions.insert(session, at: 0)
        next.activeSession = nil
        return commit(next)
    }

    @discardableResult
    func removeSession(_ id: UUID) -> Bool {
        var next = archive
        next.completedSessions.removeAll { $0.id == id }
        return commit(next)
    }

    func exportSession(_ session: VocalPracticeSession) -> URL? {
        let dates = ISO8601DateFormatter()
        let title = Self.csvField(session.title)
        let header = "recorded_at_utc,title,section,key_adjustment_semitones,with_backing_track,result,note"
        let rows = session.takes.map { take in
            [dates.string(from: take.recordedAt), title, take.section.rawValue, String(take.semitones),
             String(take.withBacking), take.result.rawValue, Self.csvField(take.note)].joined(separator: ",")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VocalExports", isDirectory: true)
        let url = folder.appendingPathComponent("micon-session-\(session.id.uuidString).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(([header] + rows).joined(separator: "\r\n").appending("\r\n").utf8)
                .write(to: url, options: .atomic)
            storageMessage = nil
            return url
        } catch {
            storageMessage = "The practice export could not be created. Please try again."
            return nil
        }
    }

    private static func csvField(_ value: String) -> String {
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let text = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    @discardableResult
    private func commit(_ next: VocalJournalArchive) -> Bool {
        guard available else { return false }
        do {
            try JSONEncoder().encode(next)
                .write(to: archiveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            storageMessage = nil
            return true
        } catch {
            storageMessage = "This change could not be saved. Please try again."
            return false
        }
    }
}
