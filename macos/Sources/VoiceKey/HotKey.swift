import Carbon.HIToolbox
import Foundation

/// Global hotkey via Carbon RegisterEventHotKey — works without Accessibility
/// permission and consumes the keystroke. Reports both press and release, so
/// the caller can implement toggle and hold-to-talk on one key.
final class HotKey {
    /// False when the combo is already claimed by another app — the caller has to
    /// say so rather than report itself ready.
    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let onRelease: () -> Void

    init(keyCode: UInt32, modifiers: UInt32,
         onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            let hk = Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                hk.onRelease()
            } else {
                hk.onPress()
            }
            return noErr
        }, 2, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hkID = EventHotKeyID(signature: OSType(0x564B_4559) /* 'VKEY' */, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
        Log.line("hotkey registration status=\(status) (0 = ok)")
    }

    deinit {
        if let h = hotKeyRef { UnregisterEventHotKey(h) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}
