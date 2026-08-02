import AppKit
import Foundation

@MainActor
final class ClipboardMonitor: NSObject {
    private let pasteboard: NSPasteboard
    private let historyStore: HistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var finalizeTask: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard = .general,
        historyStore: HistoryStore
    ) {
        self.pasteboard = pasteboard
        self.historyStore = historyStore
        self.lastChangeCount = pasteboard.changeCount
        super.init()
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(
            timeInterval: 0.45,
            target: self,
            selector: #selector(pollPasteboard),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        finalizeTask?.cancel()
        finalizeTask = nil
    }

    func markCurrentChangeAsHandled() {
        lastChangeCount = pasteboard.changeCount
    }

    @objc
    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let pending = Self.readPendingCapture(from: pasteboard) else { return }
        let mode = AppSettings.historyContentMode
        guard mode.stores(pending.kind) else { return }

        switch pending {
        case .ready(let capture):
            historyStore.add(capture)
        case .image(let payload, let pasteboardType):
            finalizeTask?.cancel()
            finalizeTask = Task { [weak self] in
                let capture = await Task.detached(priority: .utility) {
                    ClipboardPayloadCodec.finalizeImageCapture(
                        payload: payload,
                        pasteboardType: pasteboardType
                    )
                }.value
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, mode.stores(capture.kind) else { return }
                    self.historyStore.add(capture)
                }
            }
        }
    }

    /// Reads pasteboard on the calling thread (must be main for `.general`).
    static func capture(from pasteboard: NSPasteboard) -> ClipboardCapture? {
        switch readPendingCapture(from: pasteboard) {
        case .ready(let capture):
            return capture
        case .image(let payload, let pasteboardType):
            return ClipboardPayloadCodec.finalizeImageCapture(
                payload: payload,
                pasteboardType: pasteboardType
            )
        case nil:
            return nil
        }
    }

    private enum PendingCapture: Sendable {
        case ready(ClipboardCapture)
        case image(payload: Data, pasteboardType: String)

        var kind: ClipboardEntryKind {
            switch self {
            case .ready(let capture): capture.kind
            case .image: .image
            }
        }
    }

    private static func readPendingCapture(from pasteboard: NSPasteboard) -> PendingCapture? {
        if let fileCapture = makeFileCapture(from: pasteboard) {
            return .ready(fileCapture)
        }

        if let png = pasteboard.data(forType: .png) {
            return .image(payload: png, pasteboardType: NSPasteboard.PasteboardType.png.rawValue)
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return .image(payload: tiff, pasteboardType: NSPasteboard.PasteboardType.tiff.rawValue)
        }

        if let urlString = pasteboard.string(forType: .URL), !urlString.isEmpty {
            return .ready(ClipboardPayloadCodec.textCapture(urlString, kind: .url))
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return nil
        }

        let kind: ClipboardEntryKind
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            kind = .url
        } else {
            kind = .text
        }
        return .ready(ClipboardPayloadCodec.textCapture(text, kind: kind))
    }

    private static func makeFileCapture(
        from pasteboard: NSPasteboard
    ) -> ClipboardCapture? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) else {
            return nil
        }

        let paths = objects.compactMap { ($0 as? URL)?.path }
        guard !paths.isEmpty,
              let payload = try? ClipboardPayloadCodec.encodeFilePaths(paths) else {
            return nil
        }

        let firstName = URL(fileURLWithPath: paths[0]).lastPathComponent
        let title: String
        if paths.count == 1 {
            title = firstName
        } else {
            title = String(localized: "\(firstName) and \(paths.count - 1) more")
        }
        let subtitle: String
        if paths.count == 1 {
            subtitle = paths[0]
        } else {
            subtitle = String(localized: "\(paths.count) files")
        }
        return ClipboardCapture(
            kind: .files,
            title: title,
            subtitle: subtitle,
            payload: payload,
            pasteboardType: NSPasteboard.PasteboardType.fileURL.rawValue,
            contentHash: ClipboardPayloadCodec.hash(kind: .files, payload: payload)
        )
    }
}
