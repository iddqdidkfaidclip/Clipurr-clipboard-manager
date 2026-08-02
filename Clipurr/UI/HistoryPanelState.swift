import Foundation
import Observation

@MainActor
@Observable
final class HistoryPanelState {
    var selectedID: UUID?
    var statusMessage: String?
    /// Snapshot when the panel opened; relative timestamps freeze against this.
    var openedAt = Date()
    /// Opened via Secure Paste (⇧⌃⌘V) — hide content even when mode is Secure Paste only.
    var openedViaSecurePaste = false
    /// Snapshot of blur preference when the panel opened (avoids @AppStorage dual access).
    var hideCopiedContentMode: HideCopiedContentMode = .securePasteOnly
    /// Snapshot of history content mode for empty-state copy.
    var historyContentMode: HistoryContentMode = .textAndImages

    var shouldHideCopiedContent: Bool {
        switch hideCopiedContentMode {
        case .always:
            true
        case .securePasteOnly:
            openedViaSecurePaste
        }
    }

    func reset(entries: [ClipboardEntry], securePaste: Bool = false) {
        selectedID = entries.first?.id
        statusMessage = nil
        openedAt = Date()
        openedViaSecurePaste = securePaste
        hideCopiedContentMode = AppSettings.hideCopiedContentMode
        historyContentMode = AppSettings.historyContentMode
    }

    func moveSelection(by offset: Int, entries: [ClipboardEntry]) {
        guard !entries.isEmpty else {
            selectedID = nil
            return
        }
        let currentIndex = entries.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), entries.count - 1)
        selectedID = entries[nextIndex].id
    }

    func selectedEntry(in entries: [ClipboardEntry]) -> ClipboardEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }
}
