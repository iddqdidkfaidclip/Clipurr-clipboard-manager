import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HistoryStore {
    private let context: ModelContext
    private let limitProvider: () -> Int
    private let crypto: HistoryCryptoService
    private let encryptionEnabled: () -> Bool

    private(set) var entries: [ClipboardEntry] = []
    private(set) var lastError: String?

    init(
        container: ModelContainer,
        limitProvider: @escaping () -> Int = { AppSettings.historyLimit },
        crypto: HistoryCryptoService = .shared,
        encryptionEnabled: @escaping () -> Bool = { AppSettings.encryptHistory }
    ) {
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.limitProvider = limitProvider
        self.crypto = crypto
        self.encryptionEnabled = encryptionEnabled
        ensureEncryptionMatchesSetting()
        refresh()
    }

    @discardableResult
    func add(_ capture: ClipboardCapture, at date: Date = .now) -> ClipboardEntry {
        if let newest = entries.first, newest.contentHash == capture.contentHash {
            newest.createdAt = date
            if newest.thumbnailData == nil, let thumbnail = capture.thumbnailData {
                do {
                    newest.thumbnailData = newest.isContentEncrypted
                        ? try crypto.seal(thumbnail)
                        : thumbnail
                    try context.save()
                    lastError = nil
                } catch {
                    lastError = error.localizedDescription
                    refresh()
                }
            } else {
                do {
                    try context.save()
                    lastError = nil
                } catch {
                    lastError = error.localizedDescription
                    refresh()
                }
            }
            entries.removeAll { $0.id == newest.id }
            entries.insert(newest, at: 0)
            return newest
        }

        let entry = ClipboardEntry(createdAt: date, capture: capture)
        do {
            if encryptionEnabled() {
                try entry.encryptContent(using: crypto)
            }
            context.insert(entry)
            try context.save()
            try pruneExcessEntries()
            entries.insert(entry, at: 0)
            let limit = max(1, limitProvider())
            if entries.count > limit {
                entries = Array(entries.prefix(limit))
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            refresh()
        }
        return entry
    }

    /// Marks an entry as newest without reordering `entries` (avoids UI jump while the panel is open).
    func touchCreatedAt(_ entry: ClipboardEntry, at date: Date = .now) {
        entry.createdAt = date
        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clear() {
        do {
            try context.delete(model: ClipboardEntry.self)
            try context.save()
            entries = []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeAll(ofKind kind: ClipboardEntryKind) {
        let rawValue = kind.rawValue
        do {
            try context.delete(
                model: ClipboardEntry.self,
                where: #Predicate<ClipboardEntry> { entry in
                    entry.kindRawValue == rawValue
                }
            )
            try context.save()
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pruneToCurrentLimit() {
        do {
            try pruneExcessEntries()
            refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Encrypt or decrypt all rows so on-disk state matches the setting.
    func setEncryptionEnabled(_ enabled: Bool) {
        AppSettings.encryptHistory = enabled
        ensureEncryptionMatchesSetting()
        refresh()
    }

    func refresh() {
        do {
            var descriptor = FetchDescriptor<ClipboardEntry>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = max(1, limitProvider())
            entries = try context.fetch(descriptor)
            lastError = nil
        } catch {
            entries = []
            lastError = error.localizedDescription
        }
    }

    /// Aligns every stored row with `encryptionEnabled()` without changing the preference.
    func ensureEncryptionMatchesSetting() {
        let shouldEncrypt = encryptionEnabled()
        do {
            let descriptor = FetchDescriptor<ClipboardEntry>()
            let all = try context.fetch(descriptor)
            for entry in all {
                if shouldEncrypt, !entry.isContentEncrypted {
                    try entry.encryptContent(using: crypto)
                    try context.save()
                } else if !shouldEncrypt, entry.isContentEncrypted {
                    try entry.decryptContent(using: crypto)
                    try context.save()
                }
            }
            if !shouldEncrypt {
                HistoryCryptoService.deleteStoredKey()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            refresh()
        }
    }

    /// Deletes rows beyond the limit without loading the kept prefix.
    private func pruneExcessEntries() throws {
        let limit = max(1, limitProvider())
        var descriptor = FetchDescriptor<ClipboardEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = limit
        let stale = try context.fetch(descriptor)
        guard !stale.isEmpty else { return }
        for entry in stale {
            context.delete(entry)
        }
        try context.save()
    }
}
