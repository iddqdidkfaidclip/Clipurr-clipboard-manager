import AppKit
import CryptoKit
import SwiftData
import SwiftUI
import XCTest
@testable import Clipurr

final class ClipurrTests: XCTestCase {
    func testFilePathsRoundTrip() throws {
        let paths = ["/tmp/example.txt", "/Users/test/Picture.png"]
        let data = try ClipboardPayloadCodec.encodeFilePaths(paths)
        XCTAssertEqual(try ClipboardPayloadCodec.decodeFilePaths(data), paths)
    }

    func testTextAndURLCaptureKinds() {
        let text = ClipboardPayloadCodec.textCapture("Hello\nworld")
        let url = ClipboardPayloadCodec.textCapture(
            "https://example.com",
            kind: .url
        )

        XCTAssertEqual(text.kind, .text)
        XCTAssertEqual(text.title, "Hello")
        XCTAssertEqual(url.kind, .url)
        XCTAssertNotEqual(text.contentHash, url.contentHash)
        XCTAssertNil(text.thumbnailData)
    }

    func testHashHexEncodingIsStableAndCompact() {
        let payload = Data("clipurr".utf8)
        let hash = ClipboardPayloadCodec.hash(kind: .text, payload: payload)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(
            hash,
            ClipboardPayloadCodec.hash(kind: .text, payload: payload)
        )
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }

    func testImageFinalizeProducesThumbnailWithoutFullNSImageInUIPath() throws {
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let capture = ClipboardPayloadCodec.finalizeImageCapture(
            payload: imageData,
            pasteboardType: NSPasteboard.PasteboardType.png.rawValue
        )

        XCTAssertEqual(capture.kind, .image)
        XCTAssertEqual(capture.payload, imageData)
        let thumbnail = try XCTUnwrap(capture.thumbnailData)
        XCTAssertFalse(thumbnail.isEmpty)
        XCTAssertNotNil(NSImage(data: thumbnail))
        XCTAssertNotNil(ImagePreviewCodec.pixelSize(of: imageData))
    }

    func testFilesAreAvailableHelper() throws {
        let existing = try ClipboardPayloadCodec.encodeFilePaths(["/tmp"])
        let missing = try ClipboardPayloadCodec.encodeFilePaths(["/path/that/does/not/exist-\(UUID().uuidString)"])
        XCTAssertTrue(ClipboardPayloadCodec.filesAreAvailable(payload: existing))
        XCTAssertFalse(ClipboardPayloadCodec.filesAreAvailable(payload: missing))
    }

    @MainActor
    func testPasteboardRecognizesTextImageAndFiles() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ClipurrTests.\(UUID().uuidString)")
        )

        pasteboard.clearContents()
        pasteboard.setString("Plain text", forType: .string)
        XCTAssertEqual(ClipboardMonitor.capture(from: pasteboard)?.kind, .text)

        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)
        let imageCapture = try XCTUnwrap(ClipboardMonitor.capture(from: pasteboard))
        XCTAssertEqual(imageCapture.kind, .image)
        XCTAssertEqual(imageCapture.payload, imageData)
        XCTAssertNotNil(imageCapture.thumbnailData)

        pasteboard.clearContents()
        pasteboard.writeObjects([NSURL(fileURLWithPath: "/tmp/example.txt")])
        let filesCapture = try XCTUnwrap(ClipboardMonitor.capture(from: pasteboard))
        XCTAssertEqual(filesCapture.kind, .files)
        XCTAssertEqual(
            try ClipboardPayloadCodec.decodeFilePaths(filesCapture.payload),
            ["/tmp/example.txt"]
        )
    }

    @MainActor
    func testImagePayloadSurvivesPersistenceWithThumbnail() throws {
        let store = try makeStore(limit: 10)
        let payload = Data([0x89, 0x50, 0x4E, 0x47])
        let thumbnail = Data([0xFF, 0xD8, 0xFF])
        let capture = ClipboardCapture(
            kind: .image,
            title: "Image",
            subtitle: "1 × 1 px",
            payload: payload,
            pasteboardType: "public.png",
            contentHash: ClipboardPayloadCodec.hash(kind: .image, payload: payload),
            thumbnailData: thumbnail
        )

        store.add(capture)

        let entries = store.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.payload, payload)
        XCTAssertEqual(entries.first?.thumbnailData, thumbnail)
        XCTAssertEqual(entries.first?.kind, .image)
    }

    @MainActor
    func testHistoryPrunesToLimitAndKeepsNewestFirst() throws {
        let store = try makeStore(limit: 10)
        let start = Date(timeIntervalSince1970: 1_000)

        for index in 0..<12 {
            let capture = ClipboardPayloadCodec.textCapture("Item \(index)")
            store.add(
                capture,
                at: start.addingTimeInterval(TimeInterval(index))
            )
        }

        let entries = store.entries
        XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first?.title, "Item 11")
        XCTAssertEqual(entries.last?.title, "Item 2")
    }

    @MainActor
    func testConsecutiveDuplicateIsMerged() throws {
        let store = try makeStore(limit: 10)
        let capture = ClipboardPayloadCodec.textCapture("Same value")

        store.add(capture, at: Date(timeIntervalSince1970: 100))
        store.add(capture, at: Date(timeIntervalSince1970: 200))

        let entries = store.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entries.first?.createdAt,
            Date(timeIntervalSince1970: 200)
        )
    }

    @MainActor
    func testRemoveAllOfKindUsesPredicatePath() throws {
        let store = try makeStore(limit: 20)
        store.add(ClipboardPayloadCodec.textCapture("keep me"))
        store.add(ClipboardPayloadCodec.textCapture(
            "https://example.com",
            kind: .url
        ))

        let imagePayload = Data([0x89, 0x50, 0x4E, 0x47])
        store.add(
            ClipboardCapture(
                kind: .image,
                title: "Image",
                subtitle: "1 × 1 px",
                payload: imagePayload,
                pasteboardType: "public.png",
                contentHash: ClipboardPayloadCodec.hash(kind: .image, payload: imagePayload),
                thumbnailData: Data([0x01])
            )
        )

        store.removeAll(ofKind: .image)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertFalse(store.entries.contains { $0.kind == .image })
        XCTAssertTrue(store.entries.contains { $0.kind == .text })
        XCTAssertTrue(store.entries.contains { $0.kind == .url })
    }

    @MainActor
    func testPruneToCurrentLimitTrimsEntries() throws {
        let store = try makeStore(limit: 5)
        let start = Date(timeIntervalSince1970: 5_000)
        for index in 0..<8 {
            store.add(
                ClipboardPayloadCodec.textCapture("Trim \(index)"),
                at: start.addingTimeInterval(TimeInterval(index))
            )
        }
        XCTAssertEqual(store.entries.count, 5)

        // Simulate a lower limit by rebuilding with a tighter provider after inserts.
        let tightStore = try makeStore(limit: 3)
        for index in 0..<6 {
            tightStore.add(
                ClipboardPayloadCodec.textCapture("Tight \(index)"),
                at: start.addingTimeInterval(TimeInterval(index))
            )
        }
        tightStore.pruneToCurrentLimit()
        XCTAssertEqual(tightStore.entries.count, 3)
        XCTAssertEqual(tightStore.entries.first?.title, "Tight 5")
    }

    @MainActor
    func testHistoryContentModeStoresKinds() {
        XCTAssertTrue(HistoryContentMode.textOnly.stores(.text))
        XCTAssertTrue(HistoryContentMode.textOnly.stores(.url))
        XCTAssertFalse(HistoryContentMode.textOnly.stores(.image))
        XCTAssertFalse(HistoryContentMode.textOnly.stores(.files))

        XCTAssertTrue(HistoryContentMode.textAndImages.stores(.image))
        XCTAssertFalse(HistoryContentMode.textAndImages.stores(.files))

        XCTAssertTrue(HistoryContentMode.textImagesAndFiles.stores(.image))
        XCTAssertTrue(HistoryContentMode.textImagesAndFiles.stores(.files))
    }

    @MainActor
    private func makeStore(
        limit: Int,
        encrypt: Bool = false,
        crypto: HistoryCryptoService = .ephemeral()
    ) throws -> HistoryStore {
        let schema = Schema([ClipboardEntry.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        return HistoryStore(
            container: container,
            limitProvider: { limit },
            crypto: crypto,
            encryptionEnabled: { encrypt }
        )
    }

    func testHistoryCryptoRoundTripsDataAndStrings() throws {
        let crypto = HistoryCryptoService.ephemeral()
        let payload = Data("secret clipboard".utf8)
        let sealed = try crypto.seal(payload)
        XCTAssertNotEqual(sealed, payload)
        XCTAssertEqual(try crypto.open(sealed), payload)

        let title = "Password: hunter2"
        let sealedTitle = try crypto.sealString(title)
        XCTAssertNotEqual(sealedTitle, title)
        XCTAssertEqual(try crypto.openString(sealedTitle), title)
    }

    @MainActor
    func testEncryptedHistoryHidesPlaintextOnDiskButExposesAccessors() throws {
        let crypto = HistoryCryptoService.ephemeral()
        let store = try makeStore(limit: 10, encrypt: true, crypto: crypto)
        let capture = ClipboardPayloadCodec.textCapture("Top secret note")

        store.add(capture)

        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(entry.isContentEncrypted)
        XCTAssertNotEqual(entry.title, "Top secret note")
        XCTAssertNotEqual(entry.payload, capture.payload)
        XCTAssertEqual(entry.plaintextTitle(using: crypto), "Top secret note")
        XCTAssertEqual(entry.plaintextPayload(using: crypto), capture.payload)
    }

    @MainActor
    func testEncryptionToggleMigratesExistingRows() throws {
        let crypto = HistoryCryptoService.ephemeral()
        var encrypt = false
        let schema = Schema([ClipboardEntry.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let store = HistoryStore(
            container: container,
            limitProvider: { 10 },
            crypto: crypto,
            encryptionEnabled: { encrypt }
        )

        store.add(ClipboardPayloadCodec.textCapture("Migrate me"))
        let before = try XCTUnwrap(store.entries.first)
        XCTAssertFalse(before.isContentEncrypted)
        XCTAssertEqual(before.title, "Migrate me")

        encrypt = true
        store.ensureEncryptionMatchesSetting()
        store.refresh()

        let encrypted = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(encrypted.isContentEncrypted)
        XCTAssertNotEqual(encrypted.title, "Migrate me")
        XCTAssertEqual(encrypted.plaintextTitle(using: crypto), "Migrate me")

        encrypt = false
        store.ensureEncryptionMatchesSetting()
        store.refresh()

        let decrypted = try XCTUnwrap(store.entries.first)
        XCTAssertFalse(decrypted.isContentEncrypted)
        XCTAssertEqual(decrypted.title, "Migrate me")
        XCTAssertEqual(decrypted.payload, Data("Migrate me".utf8))
    }

    @MainActor
    func testEncryptedDuplicateMergesThumbnail() throws {
        let crypto = HistoryCryptoService.ephemeral()
        let store = try makeStore(limit: 10, encrypt: true, crypto: crypto)
        let payload = Data([0x89, 0x50, 0x4E, 0x47])
        let hash = ClipboardPayloadCodec.hash(kind: .image, payload: payload)

        store.add(
            ClipboardCapture(
                kind: .image,
                title: "Image",
                subtitle: "1 × 1 px",
                payload: payload,
                pasteboardType: "public.png",
                contentHash: hash,
                thumbnailData: nil
            )
        )
        store.add(
            ClipboardCapture(
                kind: .image,
                title: "Image",
                subtitle: "1 × 1 px",
                payload: payload,
                pasteboardType: "public.png",
                contentHash: hash,
                thumbnailData: Data([0xFF, 0xD8, 0xFF])
            )
        )

        XCTAssertEqual(store.entries.count, 1)
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertTrue(entry.isContentEncrypted)
        XCTAssertEqual(
            entry.plaintextThumbnailData(using: crypto),
            Data([0xFF, 0xD8, 0xFF])
        )
    }

    // MARK: - Codec edge cases

    func testFilesAreAvailableRejectsCorruptPayload() {
        XCTAssertFalse(ClipboardPayloadCodec.filesAreAvailable(payload: Data()))
        XCTAssertFalse(ClipboardPayloadCodec.filesAreAvailable(payload: Data("{}".utf8)))
        XCTAssertFalse(ClipboardPayloadCodec.filesAreAvailable(payload: Data("not-json".utf8)))
    }

    func testFilesAreAvailableEmptyPathList() throws {
        let empty = try ClipboardPayloadCodec.encodeFilePaths([])
        XCTAssertTrue(ClipboardPayloadCodec.filesAreAvailable(payload: empty))
    }

    func testHashDiffersByKindForSamePayload() {
        let payload = Data("same".utf8)
        XCTAssertNotEqual(
            ClipboardPayloadCodec.hash(kind: .text, payload: payload),
            ClipboardPayloadCodec.hash(kind: .url, payload: payload)
        )
        XCTAssertNotEqual(
            ClipboardPayloadCodec.hash(kind: .text, payload: payload),
            ClipboardPayloadCodec.hash(kind: .image, payload: payload)
        )
    }

    func testTextCaptureTruncatesTitleAndHandlesWhitespace() {
        let long = String(repeating: "a", count: 200)
        let capture = ClipboardPayloadCodec.textCapture(long)
        XCTAssertEqual(capture.title.count, 120)

        let blank = ClipboardPayloadCodec.textCapture("   \n\n  ")
        XCTAssertEqual(blank.title, String(localized: "Empty text"))
    }

    func testUnicodeFilePathsRoundTrip() throws {
        let paths = ["/tmp/фото 🐈.txt", "/Users/test/文件.png"]
        let data = try ClipboardPayloadCodec.encodeFilePaths(paths)
        XCTAssertEqual(try ClipboardPayloadCodec.decodeFilePaths(data), paths)
    }

    func testImagePreviewCodecRejectsGarbage() {
        XCTAssertNil(ImagePreviewCodec.pixelSize(of: Data([0x00, 0x01, 0x02])))
        XCTAssertNil(ImagePreviewCodec.makeThumbnailJPEG(from: Data([0xDE, 0xAD])))
    }

    // MARK: - Crypto edge cases

    func testHistoryCryptoRejectsInvalidCiphertext() {
        let crypto = HistoryCryptoService.ephemeral()
        XCTAssertThrowsError(try crypto.open(Data([0x01, 0x02, 0x03]))) { error in
            XCTAssertTrue(error is CryptoKitError || error is HistoryCryptoError)
        }
        XCTAssertThrowsError(try crypto.openString("%%%not-base64%%%")) { error in
            guard let cryptoError = error as? HistoryCryptoError else {
                return XCTFail("Expected HistoryCryptoError")
            }
            XCTAssertEqual(cryptoError, .invalidCiphertext)
        }
    }

    func testHistoryCryptoRoundTripsEmptyPayload() throws {
        let crypto = HistoryCryptoService.ephemeral()
        let sealed = try crypto.seal(Data())
        XCTAssertEqual(try crypto.open(sealed), Data())
        XCTAssertEqual(try crypto.openString(try crypto.sealString("")), "")
    }

    func testHistoryCryptoWrongKeyCannotOpen() throws {
        let keyA = SymmetricKey(size: .bits256)
        let keyB = SymmetricKey(size: .bits256)
        let cryptoA = HistoryCryptoService.ephemeral(keyA)
        let cryptoB = HistoryCryptoService.ephemeral(keyB)
        let sealed = try cryptoA.seal(Data("secret".utf8))
        XCTAssertThrowsError(try cryptoB.open(sealed))
    }

    @MainActor
    func testEncryptContentIsAtomicOnFailure() throws {
        let key = SymmetricKey(size: .bits256)
        let counter = CallCounter()
        let flaky = HistoryCryptoService(keyProvider: {
            // title + subtitle + payload succeed; thumbnail seal fails.
            if counter.next() >= 4 {
                throw HistoryCryptoError.sealingFailed
            }
            return key
        })

        let entry = ClipboardEntry(
            capture: ClipboardCapture(
                kind: .image,
                title: "Image",
                subtitle: "1 × 1 px",
                payload: Data([0x89, 0x50, 0x4E, 0x47]),
                pasteboardType: "public.png",
                contentHash: "hash",
                thumbnailData: Data([0xFF, 0xD8, 0xFF])
            )
        )

        XCTAssertThrowsError(try entry.encryptContent(using: flaky))
        XCTAssertFalse(entry.isContentEncrypted)
        XCTAssertEqual(entry.title, "Image")
        XCTAssertEqual(entry.subtitle, "1 × 1 px")
        XCTAssertEqual(entry.payload, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(entry.thumbnailData, Data([0xFF, 0xD8, 0xFF]))
    }

    @MainActor
    func testDecryptContentIsAtomicOnFailure() throws {
        let realKey = SymmetricKey(size: .bits256)
        let encryptor = HistoryCryptoService.ephemeral(realKey)
        let entry = ClipboardEntry(
            capture: ClipboardCapture(
                kind: .image,
                title: "Image",
                subtitle: "1 × 1 px",
                payload: Data([0x89, 0x50, 0x4E, 0x47]),
                pasteboardType: "public.png",
                contentHash: "hash",
                thumbnailData: Data([0xFF, 0xD8, 0xFF])
            )
        )
        try entry.encryptContent(using: encryptor)
        let beforeTitle = entry.title
        let beforeSubtitle = entry.subtitle
        let beforePayload = entry.payload
        let beforeThumbnail = entry.thumbnailData

        let counter = CallCounter()
        let failingDecrypt = HistoryCryptoService(keyProvider: {
            // title + subtitle + payload open; thumbnail open fails.
            if counter.next() >= 4 {
                throw HistoryCryptoError.invalidCiphertext
            }
            return realKey
        })
        XCTAssertThrowsError(try entry.decryptContent(using: failingDecrypt))
        XCTAssertTrue(entry.isContentEncrypted)
        XCTAssertEqual(entry.title, beforeTitle)
        XCTAssertEqual(entry.subtitle, beforeSubtitle)
        XCTAssertEqual(entry.payload, beforePayload)
        XCTAssertEqual(entry.thumbnailData, beforeThumbnail)
    }

    // MARK: - Settings / scheduler / panel state

    func testHistoryClearIntervalCalendarComponents() {
        XCTAssertNil(HistoryClearInterval.never.calendarComponent)
        XCTAssertNil(HistoryClearInterval.onRestart.calendarComponent)
        XCTAssertEqual(HistoryClearInterval.hourly.calendarComponent, .hour)
        XCTAssertEqual(HistoryClearInterval.daily.calendarComponent, .day)
        XCTAssertEqual(HistoryClearInterval.weekly.calendarComponent, .weekOfYear)
        XCTAssertEqual(HistoryClearInterval.monthly.calendarComponent, .month)
    }

    func testAppSettingsClampsHistoryLimit() {
        withIsolatedAppSettings {
            AppSettings.historyLimit = 0
            XCTAssertEqual(AppSettings.historyLimit, 1)

            AppSettings.historyLimit = 9_999
            XCTAssertEqual(AppSettings.historyLimit, AppSettings.maxHistoryLimit)

            AppSettings.historyLimit = 42
            XCTAssertEqual(AppSettings.historyLimit, 42)
        }
    }

    func testAppSettingsMigratesLegacyLanguageAndBlur() {
        withIsolatedAppSettings {
            UserDefaults.standard.removeObject(forKey: "preferredLanguage")
            UserDefaults.standard.set("english", forKey: "preferredLanguage")
            XCTAssertEqual(AppSettings.preferredLanguage, .english)

            UserDefaults.standard.removeObject(forKey: "hideCopiedContentMode")
            UserDefaults.standard.set(true, forKey: "blurUnfocusedImages")
            XCTAssertEqual(AppSettings.hideCopiedContentMode, .always)

            UserDefaults.standard.removeObject(forKey: "hideCopiedContentMode")
            UserDefaults.standard.set(false, forKey: "blurUnfocusedImages")
            XCTAssertEqual(AppSettings.hideCopiedContentMode, .securePasteOnly)
        }
    }

    func testAppSettingsEncryptHistoryDefaultsOn() {
        withIsolatedAppSettings {
            UserDefaults.standard.removeObject(forKey: "encryptHistory")
            XCTAssertTrue(AppSettings.encryptHistory)

            AppSettings.encryptHistory = false
            XCTAssertFalse(AppSettings.encryptHistory)
        }
    }

    func testAppSettingsMoveToTopOnPasteDefaultsOff() {
        withIsolatedAppSettings {
            UserDefaults.standard.removeObject(forKey: "moveToTopOnPaste")
            XCTAssertFalse(AppSettings.moveToTopOnPaste)

            AppSettings.moveToTopOnPaste = true
            XCTAssertTrue(AppSettings.moveToTopOnPaste)
        }
    }

    func testAppSettingsAppearanceDefaultsAndPersistence() {
        withIsolatedAppSettings {
            UserDefaults.standard.removeObject(forKey: "accentColor")
            UserDefaults.standard.removeObject(forKey: "appearanceTheme")
            XCTAssertEqual(AppSettings.accentColor, .blue)
            XCTAssertEqual(AppSettings.appearanceTheme, .softBlack)

            AppSettings.accentColor = .pink
            AppSettings.appearanceTheme = .light
            XCTAssertEqual(AppSettings.accentColor, .pink)
            XCTAssertEqual(AppSettings.appearanceTheme, .light)

            AppSettings.customAccentHex = 0x39C5CF
            AppSettings.accentColor = .custom
            XCTAssertEqual(AppSettings.accentColor, .custom)
            XCTAssertEqual(AppSettings.customAccentHex, 0x39C5CF)

            UserDefaults.standard.removeObject(forKey: "backgroundOpacity")
            UserDefaults.standard.removeObject(forKey: "backgroundEffect")
            XCTAssertEqual(AppSettings.backgroundOpacity, 75)
            XCTAssertEqual(AppSettings.backgroundEffect, .glass)
            AppSettings.backgroundOpacity = 40
            XCTAssertEqual(AppSettings.backgroundOpacity, 40)
            AppSettings.backgroundOpacity = 0
            XCTAssertEqual(AppSettings.backgroundOpacity, 1)
            AppSettings.backgroundOpacity = 200
            XCTAssertEqual(AppSettings.backgroundOpacity, 100)
            AppSettings.backgroundEffect = .blur
            XCTAssertEqual(AppSettings.backgroundEffect, .blur)

            XCTAssertEqual(AppearanceTheme.black.colorScheme, .dark)
            XCTAssertEqual(AppearanceTheme.softBlack.colorScheme, .dark)
            XCTAssertEqual(AppearanceTheme.light.colorScheme, .light)
        }
    }

    @MainActor
    func testHistoryClearSchedulerNeverAndOnRestart() throws {
        try withIsolatedAppSettings {
            let store = try makeStore(limit: 10)
            store.add(ClipboardPayloadCodec.textCapture("keep"))
            let scheduler = HistoryClearScheduler(historyStore: store)

            AppSettings.historyClearInterval = .never
            scheduler.performScheduledClear(isLaunch: true)
            XCTAssertEqual(store.entries.count, 1)

            AppSettings.historyClearInterval = .onRestart
            scheduler.performScheduledClear(isLaunch: false)
            XCTAssertEqual(store.entries.count, 1)

            scheduler.performScheduledClear(isLaunch: true)
            XCTAssertEqual(store.entries.count, 0)
        }
    }

    @MainActor
    func testHistoryClearSchedulerDoesNotWipeWhenLastClearMissing() throws {
        try withIsolatedAppSettings {
            let store = try makeStore(limit: 10)
            store.add(ClipboardPayloadCodec.textCapture("preserve"))
            let scheduler = HistoryClearScheduler(historyStore: store)

            AppSettings.historyClearInterval = .hourly
            AppSettings.lastAutomaticHistoryClear = nil
            scheduler.performScheduledClear(isLaunch: true)

            XCTAssertEqual(store.entries.count, 1)
            XCTAssertNotNil(AppSettings.lastAutomaticHistoryClear)
        }
    }

    @MainActor
    func testHistoryClearSchedulerClearsWhenIntervalElapsed() throws {
        try withIsolatedAppSettings {
            let store = try makeStore(limit: 10)
            store.add(ClipboardPayloadCodec.textCapture("stale"))
            let scheduler = HistoryClearScheduler(historyStore: store)

            AppSettings.historyClearInterval = .hourly
            AppSettings.lastAutomaticHistoryClear = Date(timeIntervalSince1970: 1)
            scheduler.performScheduledClear(isLaunch: false)

            XCTAssertEqual(store.entries.count, 0)
        }
    }

    @MainActor
    func testHistoryPanelStateHideAndSelection() {
        let state = HistoryPanelState()
        state.hideCopiedContentMode = .always
        state.openedViaSecurePaste = false
        XCTAssertTrue(state.shouldHideCopiedContent)

        state.hideCopiedContentMode = .securePasteOnly
        XCTAssertFalse(state.shouldHideCopiedContent)
        state.openedViaSecurePaste = true
        XCTAssertTrue(state.shouldHideCopiedContent)

        let a = ClipboardEntry(capture: ClipboardPayloadCodec.textCapture("A"))
        let b = ClipboardEntry(capture: ClipboardPayloadCodec.textCapture("B"))
        let c = ClipboardEntry(capture: ClipboardPayloadCodec.textCapture("C"))
        let entries = [a, b, c]
        let window = CircularHistoryWindow()
        state.reset(entries: entries, circularWindow: window)

        XCTAssertEqual(state.selectedID, a.id)
        XCTAssertNotNil(state.selectedTokenID)

        state.moveSelection(by: 1, circularWindow: window)
        XCTAssertEqual(state.selectedID, b.id)

        state.moveSelection(by: 1, circularWindow: window)
        XCTAssertEqual(state.selectedID, c.id)

        // Past the end → stays on last item.
        state.moveSelection(by: 1, circularWindow: window)
        XCTAssertEqual(state.selectedID, c.id)

        // Up from the first item → stays on first.
        if let topToken = window.tokens.first {
            state.select(token: topToken, entry: a)
        }
        state.moveSelection(by: -1, circularWindow: window)
        XCTAssertEqual(state.selectedID, a.id)

        window.reset(entries: [])
        state.moveSelection(by: 1, circularWindow: window)
        XCTAssertNil(state.selectedID)
        XCTAssertNil(state.selectedTokenID)
    }

    @MainActor
    func testCircularHistoryWindowIsLinearList() {
        let entries = (0..<5).map { index in
            ClipboardEntry(capture: ClipboardPayloadCodec.textCapture("Item \(index)"))
        }
        let window = CircularHistoryWindow()
        window.reset(entries: entries)

        XCTAssertEqual(window.tokens.count, entries.count)
        XCTAssertEqual(window.listTopTokenID, entries[0].id.uuidString)
        XCTAssertEqual(window.tokens.map(\.entryID), entries.map(\.id))

        let last = window.moveSelection(from: window.tokens.last?.id, by: 1)
        XCTAssertEqual(last?.entryID, entries.last?.id)

        let first = window.moveSelection(from: window.tokens.first?.id, by: -1)
        XCTAssertEqual(first?.entryID, entries.first?.id)

        window.reset(entries: [entries[0]])
        XCTAssertEqual(window.tokens.count, 1)
    }

    @MainActor
    func testTouchCreatedAtDoesNotReorderUntilRefresh() throws {
        let store = try makeStore(limit: 10)
        store.add(
            ClipboardPayloadCodec.textCapture("Older"),
            at: Date(timeIntervalSince1970: 100)
        )
        store.add(
            ClipboardPayloadCodec.textCapture("Newer"),
            at: Date(timeIntervalSince1970: 200)
        )

        let older = try XCTUnwrap(store.entries.last)
        XCTAssertEqual(older.title, "Older")
        XCTAssertEqual(store.entries.first?.title, "Newer")

        store.touchCreatedAt(older, at: Date(timeIntervalSince1970: 300))

        // In-memory order stays put so the open panel does not jump.
        XCTAssertEqual(store.entries.map(\.title), ["Newer", "Older"])
        XCTAssertEqual(older.createdAt, Date(timeIntervalSince1970: 300))

        store.refresh()
        XCTAssertEqual(store.entries.map(\.title), ["Older", "Newer"])
        XCTAssertEqual(store.entries.first?.createdAt, Date(timeIntervalSince1970: 300))
    }

    @MainActor
    func testNonConsecutiveDuplicateIsNotMerged() throws {
        let store = try makeStore(limit: 10)
        let first = ClipboardPayloadCodec.textCapture("Same")
        let other = ClipboardPayloadCodec.textCapture("Other")

        store.add(first, at: Date(timeIntervalSince1970: 1))
        store.add(other, at: Date(timeIntervalSince1970: 2))
        store.add(first, at: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(store.entries.count, 3)
    }

    // MARK: - Helpers

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private func withIsolatedAppSettings(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [
            "historyLimit",
            "didAskLaunchAtLogin",
            "preferredLanguage",
            "historyContentMode",
            "hideCopiedContentMode",
            "historyClearInterval",
            "lastAutomaticHistoryClear",
            "encryptHistory",
            "moveToTopOnPaste",
            "blurUnfocusedImages",
        ]
        let snapshot = keys.map { ($0, defaults.object(forKey: $0)) }
        keys.forEach { defaults.removeObject(forKey: $0) }
        defer {
            keys.forEach { defaults.removeObject(forKey: $0) }
            for (key, value) in snapshot {
                if let value {
                    defaults.set(value, forKey: key)
                }
            }
        }
        try body()
    }
}
