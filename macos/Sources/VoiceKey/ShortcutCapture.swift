import AppKit
import Carbon.HIToolbox

/// Tiny floating panel that captures the next key combo pressed and hands
/// back (carbonKeyCode, carbonModifiers, displayLabel). Esc or closing cancels.
final class ShortcutCapture: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    private var onCapture: ((UInt32, UInt32, String) -> Void)?

    func begin(onCapture: @escaping (UInt32, UInt32, String) -> Void) {
        end()
        self.onCapture = onCapture
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 90),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "VoiceKey Shortcut"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.delegate = self
        let label = NSTextField(wrappingLabelWithString:
            "Press the new shortcut.\nMust include ⌘, ⌃ or ⌥ — Esc cancels.")
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 22, width: 300, height: 44)
        p.contentView?.addSubview(label)
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            self?.handle(ev)
            return nil // swallow the keystroke
        }
    }

    private func handle(_ ev: NSEvent) {
        if ev.keyCode == UInt16(kVK_Escape) { end(); return }
        let f = ev.modifierFlags
        var carbon: UInt32 = 0
        if f.contains(.command) { carbon |= UInt32(cmdKey) }
        if f.contains(.option)  { carbon |= UInt32(optionKey) }
        if f.contains(.control) { carbon |= UInt32(controlKey) }
        if f.contains(.shift)   { carbon |= UInt32(shiftKey) }
        // require a non-shift modifier, else plain typing would trigger dictation
        guard carbon & ~UInt32(shiftKey) != 0 else { return }
        let label = Self.describe(ev)
        let done = onCapture
        let code = UInt32(ev.keyCode)
        end()
        done?(code, carbon, label)
    }

    static func describe(_ event: NSEvent) -> String {
        let flags = event.modifierFlags
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        switch Int(event.keyCode) {
        case kVK_Space: s += "Space"
        case kVK_Return: s += "↩"
        case kVK_Tab: s += "⇥"
        default:
            let c = event.charactersIgnoringModifiers ?? ""
            s += c.isEmpty ? "key\(event.keyCode)" : c.uppercased()
        }
        return s
    }

    func windowWillClose(_ notification: Notification) {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        onCapture = nil
        panel = nil
    }

    private func end() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
    }
}
