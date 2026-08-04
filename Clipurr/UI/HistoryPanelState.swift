import Foundation
import Observation

@MainActor
@Observable
final class HistoryPanelState {
    var selectedID: UUID?
    /// Which visual copy is focused: `0` before the break, `1` after.
    var selectedLoop = 0
    var statusMessage: String?
    /// Snapshot when the panel opened; relative timestamps freeze against this.
    var openedAt = Date()
    /// Opened via Secure Paste (⇧⌃⌘V) — hide content even when mode is Secure Paste only.
    var openedViaSecurePaste = false
    /// Snapshot of blur preference when the panel opened (avoids @AppStorage dual access).
    var hideCopiedContentMode: HideCopiedContentMode = .securePasteOnly
    /// Snapshot of history content mode for empty-state copy.
    var historyContentMode: HistoryContentMode = .textAndImages
    /// Keyboard moves animate; panel open / reset jumps instantly.
    var animateSelectionScroll = false

    var selectedScrollID: String? {
        guard let selectedID else { return nil }
        return Self.scrollID(loop: selectedLoop, entryID: selectedID)
    }

    var shouldHideCopiedContent: Bool {
        switch hideCopiedContentMode {
        case .always:
            true
        case .securePasteOnly:
            openedViaSecurePaste
        }
    }

    static func scrollID(loop: Int, entryID: UUID) -> String {
        "\(loop)-\(entryID.uuidString)"
    }

    func reset(entries: [ClipboardEntry], securePaste: Bool = false) {
        animateSelectionScroll = false
        selectedID = entries.first?.id
        selectedLoop = 0
        statusMessage = nil
        openedAt = Date()
        openedViaSecurePaste = securePaste
        hideCopiedContentMode = AppSettings.hideCopiedContentMode
        historyContentMode = AppSettings.historyContentMode
    }

    func select(_ entry: ClipboardEntry, loop: Int) {
        animateSelectionScroll = false
        selectedID = entry.id
        selectedLoop = loop
    }

    /// Moves selection by `offset`, wrapping around the ends of the list.
    func moveSelection(by offset: Int, entries: [ClipboardEntry]) {
        animateSelectionScroll = true
        guard !entries.isEmpty else {
            selectedID = nil
            selectedLoop = 0
            return
        }
        let count = entries.count
        let currentIndex = entries.firstIndex { $0.id == selectedID } ?? 0

        guard count > 1 else {
            selectedID = entries[0].id
            selectedLoop = 0
            return
        }

        if abs(offset) == 1 {
            if offset == 1, currentIndex == count - 1 {
                selectedLoop = selectedLoop == 0 ? 1 : 0
                selectedID = entries[0].id
            } else if offset == -1, currentIndex == 0 {
                if selectedLoop == 1 {
                    selectedLoop = 0
                }
                selectedID = entries[count - 1].id
            } else {
                selectedID = entries[currentIndex + offset].id
            }
            return
        }

        let nextIndex = ((currentIndex + offset) % count + count) % count
        selectedID = entries[nextIndex].id
    }

    func selectedEntry(in entries: [ClipboardEntry]) -> ClipboardEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }
}
