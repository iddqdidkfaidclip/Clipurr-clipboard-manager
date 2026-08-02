import Foundation
import SwiftData

enum ClipboardEntryKind: String, Codable, CaseIterable, Sendable {
    case text
    case url
    case image
    case files

    var displayName: String {
        switch self {
        case .text: String(localized: "Text")
        case .url: String(localized: "URL")
        case .image: String(localized: "Image")
        case .files: String(localized: "Files")
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .url: "link"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }
}

struct ClipboardCapture: Equatable, Sendable {
    let kind: ClipboardEntryKind
    let title: String
    let subtitle: String
    let payload: Data
    let pasteboardType: String
    let contentHash: String
    let thumbnailData: Data?

    init(
        kind: ClipboardEntryKind,
        title: String,
        subtitle: String,
        payload: Data,
        pasteboardType: String,
        contentHash: String,
        thumbnailData: Data? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
        self.pasteboardType = pasteboardType
        self.contentHash = contentHash
        self.thumbnailData = thumbnailData
    }
}

@Model
final class ClipboardEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var kindRawValue: String
    /// Plaintext, or AES-GCM ciphertext (base64) when `isContentEncrypted`.
    var title: String
    /// Plaintext, or AES-GCM ciphertext (base64) when `isContentEncrypted`.
    var subtitle: String
    @Attribute(.externalStorage) var payload: Data
    var pasteboardType: String
    var contentHash: String
    var thumbnailData: Data?
    /// When true, title/subtitle/payload/thumbnailData are sealed with HistoryCrypto.
    var isContentEncrypted: Bool = false

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        capture: ClipboardCapture,
        isContentEncrypted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRawValue = capture.kind.rawValue
        self.title = capture.title
        self.subtitle = capture.subtitle
        self.payload = capture.payload
        self.pasteboardType = capture.pasteboardType
        self.contentHash = capture.contentHash
        self.thumbnailData = capture.thumbnailData
        self.isContentEncrypted = isContentEncrypted
    }

    var kind: ClipboardEntryKind {
        ClipboardEntryKind(rawValue: kindRawValue) ?? .text
    }

    func plaintextTitle(using crypto: HistoryCryptoService = .shared) -> String {
        guard isContentEncrypted else { return title }
        return (try? crypto.openString(title)) ?? ""
    }

    func plaintextSubtitle(using crypto: HistoryCryptoService = .shared) -> String {
        guard isContentEncrypted else { return subtitle }
        return (try? crypto.openString(subtitle)) ?? ""
    }

    func plaintextPayload(using crypto: HistoryCryptoService = .shared) -> Data {
        guard isContentEncrypted else { return payload }
        return (try? crypto.open(payload)) ?? Data()
    }

    func plaintextThumbnailData(using crypto: HistoryCryptoService = .shared) -> Data? {
        guard let thumbnailData else { return nil }
        guard isContentEncrypted else { return thumbnailData }
        return try? crypto.open(thumbnailData)
    }

    func encryptContent(using crypto: HistoryCryptoService) throws {
        guard !isContentEncrypted else { return }
        // Seal into locals first so a mid-flight failure never leaves mixed plaintext/ciphertext.
        let sealedTitle = try crypto.sealString(title)
        let sealedSubtitle = try crypto.sealString(subtitle)
        let sealedPayload = try crypto.seal(payload)
        let sealedThumbnail = try thumbnailData.map { try crypto.seal($0) }
        title = sealedTitle
        subtitle = sealedSubtitle
        payload = sealedPayload
        thumbnailData = sealedThumbnail
        isContentEncrypted = true
    }

    func decryptContent(using crypto: HistoryCryptoService) throws {
        guard isContentEncrypted else { return }
        let plainTitle = try crypto.openString(title)
        let plainSubtitle = try crypto.openString(subtitle)
        let plainPayload = try crypto.open(payload)
        let plainThumbnail = try thumbnailData.map { try crypto.open($0) }
        title = plainTitle
        subtitle = plainSubtitle
        payload = plainPayload
        thumbnailData = plainThumbnail
        isContentEncrypted = false
    }
}
