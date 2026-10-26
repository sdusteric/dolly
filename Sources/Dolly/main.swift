import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--shot" {
    // Never reaches NSApplication: no run loop, no window, no activation.
    ShotMode.run(arguments)
}

// Replaced in Task 20 by the real app delegate.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.run()
