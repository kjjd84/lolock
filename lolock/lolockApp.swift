import SwiftUI
import AppKit
import LaunchAtLogin

@main
struct lolockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { } // menu bar only, no windows
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Config
    // private static let leagueBundle = "com.riotgames.LeagueofLegends.LeagueClientUx"
    private static let leagueBundle = "com.riotgames.LeagueofLegends.GameClient"
    private var throttleInterval: TimeInterval = 0.008 // ~120 Hz default

    // UI / State
    private var statusItem: NSStatusItem!
    private var eventMonitor: Any?
    private var screenFrame: CGRect = .zero
    private var screenHeight: CGFloat = 0
    private var isLeagueActive = false

    // Smooth-motion deltas
    private var lastTime: TimeInterval = 0
    private var lastDeltaX: CGFloat = 0
    private var lastDeltaY: CGFloat = 0
    private var lastProcessedTime: TimeInterval = 0

    // MARK: Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        setupObservers()

        if !AXIsProcessTrusted() {
            NSLog("Enable Accessibility: System Settings → Privacy & Security → Accessibility.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeObservers()
        stopLocking()
    }

    // MARK: Menu Bar
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: nil)

        let menu = NSMenu()

        // Launch at Login toggle
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        // Quit option
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.isEnabled.toggle()
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func quitApp() {
        stopLocking()
        NSApp.terminate(nil)
    }

    // MARK: Observers
    private func setupObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDeactivated(_:)),
                       name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
    }

    private func removeObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.leagueBundle else { return }

        // Inline detection (no async)
        let frame = getLeagueWindowFrame(for: app)
        if let frame, let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            screenFrame = screen.frame
            screenHeight = screen.frame.height
            if let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()),
               mode.refreshRate > 0 {
                throttleInterval = 1.0 / Double(mode.refreshRate)
            } else {
                throttleInterval = 0.008
            }
        } else {
            screenFrame = NSScreen.main?.frame ?? .zero
            screenHeight = screenFrame.height
            throttleInterval = 0.008
        }

        isLeagueActive = true
        startLocking()
    }

    @objc private func appDeactivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.leagueBundle else { return }
        isLeagueActive = false
        stopLocking()
    }

    // MARK: Mouse Lock Logic
    private func startLocking() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            guard let self = self, self.isLeagueActive, self.screenFrame != .zero else { return }

            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastProcessedTime < self.throttleInterval { return }
            self.lastProcessedTime = now

            if self.lastTime != 0 && event.timestamp <= self.lastTime {
                self.lastDeltaX = 0; self.lastDeltaY = 0; return
            }

            let deltaX = event.deltaX - self.lastDeltaX
            let deltaY = event.deltaY - self.lastDeltaY
            let p = event.locationInWindow
            let x = p.x
            let y = self.screenHeight - p.y

            let w = self.screenFrame.width, h = self.screenFrame.height
            let xPoint = min(max(x + deltaX, 1), w - 1)
            let yPoint = min(max(y + deltaY, 1), h - 1)

            self.lastDeltaX = xPoint - x
            self.lastDeltaY = yPoint - y
            self.lastTime = now

            CGWarpMouseCursorPosition(CGPoint(x: xPoint, y: yPoint))
        }
    }

    private func stopLocking() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        lastTime = 0; lastDeltaX = 0; lastDeltaY = 0; lastProcessedTime = 0
    }

    // MARK: Accessibility
    private func getLeagueWindowFrame(for app: NSRunningApplication) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let window = winRef else { return nil }

        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXMinimizedAttribute as CFString, &minimized) == .success,
           let isMin = minimized as? Bool, isMin { return nil }

        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeRef)
        guard let posAX = posRef, let sizeAX = sizeRef else { return nil }

        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posAX as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeAX as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }
}
