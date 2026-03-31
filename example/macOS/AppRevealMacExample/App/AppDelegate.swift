import AppKit

#if DEBUG
import AppReveal
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureWindow()

        #if DEBUG
        AppReveal.start()
        AppReveal.registerStateProvider(ExampleStateContainer.shared)
        AppReveal.registerNavigationProvider(ExampleRouter.shared)
        AppReveal.registerFeatureFlagProvider(ExampleFeatureFlags.shared)
        AppReveal.registerNetworkObservable(ExampleNetworkClient.shared)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AppReveal Mac Example"
        window.center()
        window.contentViewController = MainSplitViewController()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func configureMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AppReveal Mac Example", action: nil, keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AppReveal Mac Example", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Quit AppReveal Mac Example", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        fileMenuItem.submenu = fileMenu

        NSApp.mainMenu = mainMenu
    }
}
