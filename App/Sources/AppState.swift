import SwiftUI
import MurmurCore

@MainActor
public final class AppState: ObservableObject {
    public enum Phase: Equatable { case idle, listening(locked: Bool), transcribing, polishing, downloading(Double), error(String) }

    @Published public var phase: Phase = .idle
    @Published public var polishEnabled: Bool = UserDefaults.standard.object(forKey: "polishEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(polishEnabled, forKey: "polishEnabled") }
    }
    @Published public var hotkey: HotkeyChoice = HotkeyChoice(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "fn") ?? .fn {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: "hotkey") }
    }
    @Published public var recentPeek: [HistoryEntry] = []
    @Published public var historyEntries: [HistoryEntry] = []
    @Published public var inputLevel: Float = 0

    public let history: HistoryStore
    public let vocabulary: VocabularyStore

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Murmur", isDirectory: true)
        history = (try? HistoryStore(fileURL: support.appendingPathComponent("history.json"), limit: 200))
            ?? (try! HistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("history.json")))
        vocabulary = (try? VocabularyStore(fileURL: support.appendingPathComponent("vocabulary.json")))
            ?? (try! VocabularyStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary.json")))
        recentPeek = Array(history.entries.prefix(3))
        historyEntries = history.entries
    }

    public func appendDictation(_ entry: HistoryEntry) {
        history.append(entry)
        historyEntries = history.entries
        recentPeek = Array(history.entries.prefix(3))
    }

    public func deleteDictation(id: UUID) {
        history.delete(id: id)
        historyEntries = history.entries
        recentPeek = Array(history.entries.prefix(3))
    }
}
