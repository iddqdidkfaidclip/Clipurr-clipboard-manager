import Foundation
import Observation

@MainActor
@Observable
final class HistoryPanelState {
    var selectedID: UUID?
    /// Token id in the history list (`entry uuid`).
    var selectedTokenID: String?
    var statusMessage: String?
    /// Snapshot when the panel opened; relative timestamps freeze against this.
    var openedAt = Date()
    /// Opened via Secure Paste (⇧⌃⌘V) — hide content even when mode is Secure Paste only.
    var openedViaSecurePaste = false
    /// Snapshot of blur preference when the panel opened (avoids @AppStorage dual access).
    var hideCopiedContentMode: HideCopiedContentMode = .securePasteOnly
    /// Snapshot of history content mode for empty-state copy.
    var historyContentMode: HistoryContentMode = .textAndImages
    /// Snapshot of panel size for this open session.
    var panelSize: PanelSize = .large
    /// Keyboard moves animate; panel open / reset jumps instantly.
    var animateSelectionScroll = false

    var shouldHideCopiedContent: Bool {
        switch hideCopiedContentMode {
        case .always:
            true
        case .securePasteOnly:
            openedViaSecurePaste
        }
    }

    func reset(
        entries: [ClipboardEntry],
        circularWindow: CircularHistoryWindow,
        securePaste: Bool = false
    ) {
        animateSelectionScroll = false
        panelSize = AppSettings.panelSize
        circularWindow.reset(entries: entries)
        selectedTokenID = circularWindow.listTopTokenID
        selectedID = entries.first?.id
        statusMessage = nil
        openedAt = Date()
        openedViaSecurePaste = securePaste
        hideCopiedContentMode = AppSettings.hideCopiedContentMode
        historyContentMode = AppSettings.historyContentMode
    }

    func select(token: CircularHistoryToken, entry: ClipboardEntry) {
        animateSelectionScroll = false
        selectedTokenID = token.id
        selectedID = entry.id
    }

    func select(_ entry: ClipboardEntry) {
        animateSelectionScroll = false
        selectedID = entry.id
        if selectedTokenID == entry.id.uuidString {
            return
        }
        selectedTokenID = nil
    }

    /// Moves selection by `offset`, clamping at the first and last items.
    func moveSelection(by offset: Int, circularWindow: CircularHistoryWindow) {
        animateSelectionScroll = true
        guard let token = circularWindow.moveSelection(from: selectedTokenID, by: offset) else {
            selectedID = nil
            selectedTokenID = nil
            return
        }
        selectedTokenID = token.id
        selectedID = token.entryID
    }

    func selectedEntry(in entries: [ClipboardEntry]) -> ClipboardEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }
}
