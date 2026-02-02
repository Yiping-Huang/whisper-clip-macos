import Carbon
import Foundation

final class GlobalHotKeyManager {
    private static var sharedHandler: ((EventHotKeyID) -> Void)?

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    func register() {
        GlobalHotKeyManager.sharedHandler = { [weak self] _ in
            self?.action()
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                GlobalHotKeyManager.sharedHandler?(hotKeyID)
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x57434D42), id: UInt32(1))
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
