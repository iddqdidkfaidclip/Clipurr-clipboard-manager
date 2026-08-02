import Carbon.HIToolbox
import Foundation

enum HotKeyAction: UInt32 {
    case paste = 1
    case securePaste = 2
}

enum HotKeyRegistrationError: LocalizedError {
    case handler(OSStatus)
    case registration(HotKeyAction, OSStatus)

    var errorDescription: String? {
        switch self {
        case .handler(let status):
            return String(localized: "Could not install the keyboard handler (error \(status))."
            )
        case .registration(let action, let status):
            let chord: String
            switch action {
            case .paste:
                chord = "⇧⌘V"
            case .securePaste:
                chord = "⇧⌃⌘V"
            }
            return String(localized: "\(chord) is already in use or could not be registered (error \(status))."
            )
        }
    }
}

final class HotKeyManager: @unchecked Sendable {
    var onPressed: (@MainActor (HotKeyAction) -> Void)?

    private var pasteHotKeyRef: EventHotKeyRef?
    private var securePasteHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let signature = OSType(0x434C_5052) // 'CLPR'

    init() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, theEvent, userData in
                guard let userData, let theEvent else { return noErr }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let action = HotKeyAction(rawValue: hotKeyID.id) else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    manager.onPressed?(action)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            throw HotKeyRegistrationError.handler(handlerStatus)
        }

        do {
            pasteHotKeyRef = try Self.register(
                action: .paste,
                modifiers: UInt32(cmdKey | shiftKey)
            )
            securePasteHotKeyRef = try Self.register(
                action: .securePaste,
                modifiers: UInt32(cmdKey | shiftKey | controlKey)
            )
        } catch {
            tearDown()
            throw error
        }
    }

    deinit {
        tearDown()
    }

    private func tearDown() {
        if let pasteHotKeyRef {
            UnregisterEventHotKey(pasteHotKeyRef)
            self.pasteHotKeyRef = nil
        }
        if let securePasteHotKeyRef {
            UnregisterEventHotKey(securePasteHotKeyRef)
            self.securePasteHotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private static func register(
        action: HotKeyAction,
        modifiers: UInt32
    ) throws -> EventHotKeyRef {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: signature,
            id: action.rawValue
        )
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw HotKeyRegistrationError.registration(action, status)
        }
        return hotKeyRef
    }
}
