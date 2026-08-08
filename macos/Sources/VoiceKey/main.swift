import AppKit

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory) // belt-and-suspenders with LSUIElement
app.run()
