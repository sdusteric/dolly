import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--shot" {
    // Never reaches NSApplication.run: no run loop, no window, no activation.
    ShotMode.run(arguments)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
