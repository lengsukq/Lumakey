import AppKit
import SwiftUI

@MainActor
final class LumakeyAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = AppViewModel()
    private var coordinator: MenuBarAndWindowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coord = MenuBarAndWindowCoordinator(viewModel: viewModel)
        self.coordinator = coord
        coord.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.handleDockReopen()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        coordinator?.buildDockMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}

@main
@MainActor
struct LumakeyMain {
    static let delegate = LumakeyAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
