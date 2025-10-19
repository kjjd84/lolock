import AppKit
import SwiftUI
import LaunchAtLogin

@main
struct lolockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("lolock", systemImage: "computermouse") {
            VStack(alignment: .leading, spacing: 10) {
                LaunchAtLogin.Toggle()
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(12)
            .frame(width: 160)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let leagueBundle = "com.riotgames.LeagueofLegends.GameClient"

    private var eventMonitor: Any?
    private var isLeagueActive = false
    private var lastTime: TimeInterval = 0
    private var lastDeltaX: CGFloat = 0
    private var lastDeltaY: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopLocking()
        removeObservers()
    }

    // MARK: - Observers
    private func setupObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDeactivated(_:)),
                       name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    private func removeObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.leagueBundle else { return }

        isLeagueActive = true
        startLocking()
    }

    @objc private func appDeactivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.leagueBundle else { return }

        isLeagueActive = false
        stopLocking()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.leagueBundle else { return }

        isLeagueActive = false
        stopLocking()
    }

    // MARK: - Mouse Lock Logic
    private func startLocking() {
        stopLocking()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            guard let self = self, self.isLeagueActive else { return }
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else { return }

            let screenFrame = screen.frame
            let flipped = event.locationInWindow.flipped(in: screenFrame)

            if self.lastTime != 0 && event.timestamp <= self.lastTime {
                self.lastDeltaX = 0
                self.lastDeltaY = 0
                return
            }

            let deltaX = event.deltaX - self.lastDeltaX
            let deltaY = event.deltaY - self.lastDeltaY

            let newX = clamp(flipped.x + deltaX,
                             minValue: screenFrame.minX + 1,
                             maxValue: screenFrame.maxX - 1)
            let newY = clamp(flipped.y + deltaY,
                             minValue: screenFrame.minY + 1,
                             maxValue: screenFrame.maxY - 1)

            self.lastDeltaX = newX - flipped.x
            self.lastDeltaY = newY - flipped.y
            self.lastTime = ProcessInfo.processInfo.systemUptime

            CGWarpMouseCursorPosition(CGPoint(x: newX, y: newY))
        }
    }

    private func stopLocking() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        lastTime = 0
        lastDeltaX = 0
        lastDeltaY = 0
    }
}

// MARK: - Helpers
private func clamp<T: Comparable>(_ value: T, minValue: T, maxValue: T) -> T {
    min(max(value, minValue), maxValue)
}

private extension NSPoint {
    func flipped(in screenFrame: CGRect) -> NSPoint {
        NSPoint(x: self.x, y: screenFrame.height - self.y)
    }
}
