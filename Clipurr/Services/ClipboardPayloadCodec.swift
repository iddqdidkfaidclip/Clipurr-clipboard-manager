import CryptoKit
import Foundation

enum ClipboardPayloadCodec {
    private static let hexLookup = Array("0123456789abcdef")

    static func encodeFilePaths(_ paths: [String]) throws -> Data {
        try JSONEncoder().encode(paths)
    }

    static func decodeFilePaths(_ data: Data) throws -> [String] {
        try JSONDecoder().decode([String].self, from: data)
    }

    static func hash(kind: ClipboardEntryKind, payload: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(0)
        input.append(payload)
        return hexString(SHA256.hash(data: input))
    }

    static func hexString(_ digest: SHA256Digest) -> String {
        var characters: [Character] = []
        characters.reserveCapacity(SHA256Digest.byteCount * 2)
        for byte in digest {
            characters.append(hexLookup[Int(byte >> 4)])
            characters.append(hexLookup[Int(byte & 0x0f)])
        }
        return String(characters)
    }

    static func textCapture(_ text: String, kind: ClipboardEntryKind = .text) -> ClipboardCapture {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = Data(text.utf8)
        let firstLine = normalized
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? normalized
        let title = String(firstLine.prefix(120))
        let lineCount = max(1, text.split(whereSeparator: \.isNewline).count)
        let subtitle: String
        if kind == .url {
            subtitle = String(localized: "Web address")
        } else {
            subtitle = String(localized: "\(text.count) characters · \(lineCount) lines")
        }

        return ClipboardCapture(
            kind: kind,
            title: title.isEmpty ? String(localized: "Empty text") : title,
            subtitle: subtitle,
            payload: payload,
            pasteboardType: kind == .url ? "public.url" : "public.utf8-plain-text",
            contentHash: hash(kind: kind, payload: payload)
        )
    }

    /// Hash + thumbnail + dimension subtitle for image payloads (safe off the main actor).
    static func finalizeImageCapture(
        payload: Data,
        pasteboardType: String
    ) -> ClipboardCapture {
        let subtitle: String
        if let size = ImagePreviewCodec.pixelSize(of: payload) {
            subtitle = String(localized: "\(size.width) × \(size.height) px")
        } else {
            subtitle = ByteCountFormatter.string(
                fromByteCount: Int64(payload.count),
                countStyle: .file
            )
        }

        return ClipboardCapture(
            kind: .image,
            title: String(localized: "Image"),
            subtitle: subtitle,
            payload: payload,
            pasteboardType: pasteboardType,
            contentHash: hash(kind: .image, payload: payload),
            thumbnailData: ImagePreviewCodec.makeThumbnailJPEG(from: payload)
        )
    }

    static func filesAreAvailable(payload: Data) -> Bool {
        guard let paths = try? decodeFilePaths(payload) else {
            return false
        }
        return paths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }
}
