import AppKit

/// Inserts text at the cursor of the frontmost app: snapshot the pasteboard,
/// write the transcript, synthesize Cmd+V, restore the snapshot.
enum TextInserter {
    /// Requires Accessibility trust for the synthetic Cmd+V; check
    /// AXIsProcessTrusted() before calling.
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var d = [NSPasteboard.PasteboardType: Data]()
            for t in item.types { d[t] = item.data(forType: t) }
            return d
        }

        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: src, virtualKey: 9 /* kVK_ANSI_V */, keyDown: down)
            ev?.flags = .maskCommand
            ev?.post(tap: .cghidEventTap)
        }

        // restore after the paste has landed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            pb.clearContents()
            let items = saved.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (t, d) in dict { item.setData(d, forType: t) }
                return item
            }
            pb.writeObjects(items)
        }
    }
}
