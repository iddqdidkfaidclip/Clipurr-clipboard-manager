import Foundation
import Observation

/// One rendered row in the history list.
struct CircularHistoryToken: Identifiable, Equatable, Sendable {
    let entryIndex: Int
    let entryID: UUID

    var id: String { entryID.uuidString }
}

/// Linear list over a fixed newest-first history. Selection clamps at the ends.
@MainActor
@Observable
final class CircularHistoryWindow {
    private(set) var tokens: [CircularHistoryToken] = []

    func reset(entries: [ClipboardEntry]) {
        tokens = entries.enumerated().map { index, entry in
            CircularHistoryToken(entryIndex: index, entryID: entry.id)
        }
    }

    var listTopTokenID: String? {
        tokens.first?.id
    }

    func entry(at token: CircularHistoryToken, in entries: [ClipboardEntry]) -> ClipboardEntry? {
        guard token.entryIndex >= 0, token.entryIndex < entries.count else { return nil }
        let entry = entries[token.entryIndex]
        guard entry.id == token.entryID else {
            return entries.first { $0.id == token.entryID }
        }
        return entry
    }

    func token(id: String?) -> CircularHistoryToken? {
        guard let id else { return nil }
        return tokens.first { $0.id == id }
    }

    /// Moves selection by `offset`, clamping at the first and last items.
    func moveSelection(
        from selectedTokenID: String?,
        by offset: Int
    ) -> CircularHistoryToken? {
        guard !tokens.isEmpty else { return nil }

        let currentIndex = tokens.firstIndex { $0.id == selectedTokenID } ?? 0
        let next = min(max(currentIndex + offset, 0), tokens.count - 1)
        return tokens[next]
    }
}
