import SwiftUI
import LaunchAtLogin

@main
struct lolockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var appState = AppState.shared
    
    var body: some Scene {
        MenuBarExtra("lolock", systemImage: "computermouse") {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("lolock").fontWeight(.bold)
                    
                    Spacer()
                    
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Width")
                        TextField("Width", text: $appState.width)
                    }

                    VStack(alignment: .leading) {
                        Text("Height")
                        TextField("Height", text: $appState.height)
                    }
                }

                LaunchAtLogin.Toggle()
            }
            .padding(20)
            .background(
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    
                    Image("bg")
                        .resizable()
                        .scaledToFill()
                        .opacity(0.1)
                        .clipped()
                }
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// credit for most code below goes to: https://github.com/mxrlkn/mouselock

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var width: String = UserDefaults.standard.string(forKey: "width") ?? "2048" {
        didSet { UserDefaults.standard.set(self.width, forKey: "width") }
    }
    
    @Published var height: String = UserDefaults.standard.string(forKey: "height") ?? "1152" {
        didSet { UserDefaults.standard.set(self.height, forKey: "height") }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var lastTime: TimeInterval = 0
    var lastDeltaX: CGFloat = 0
    var lastDeltaY: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { event in
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.riotgames.LeagueofLegends.GameClient" else {
                return
            }
            
            if self.lastTime != 0 && event.timestamp <= self.lastTime {
                self.lastDeltaX = 0
                self.lastDeltaY = 0
                return
            }

            let deltaX = event.deltaX - self.lastDeltaX
            let deltaY = event.deltaY - self.lastDeltaY
            let x = event.locationInWindow.flipped.x
            let y = event.locationInWindow.flipped.y

            guard let window = NSScreen.main?.frame.size else { return }

            let width = CGFloat(Int(AppState.shared.width) ?? Int(window.width))
            let height = CGFloat(Int(AppState.shared.height) ?? Int(window.height))

            let widthCut = ((window.width - width) / 2) + 1
            let heightCut = ((window.height - height) / 2) + 1

            let xPoint = clamp(x + deltaX, minValue: widthCut, maxValue: window.width - widthCut)
            let yPoint = clamp(y + deltaY, minValue: heightCut, maxValue: window.height - heightCut)

            self.lastDeltaX = xPoint - x
            self.lastDeltaY = yPoint - y

            CGWarpMouseCursorPosition(CGPoint(x: xPoint, y: yPoint))
            self.lastTime = ProcessInfo.processInfo.systemUptime
        }
    }
}

public func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
    return min(max(value, minValue), maxValue)
}

extension NSPoint {
    var flipped: NSPoint {
        let frame = (NSScreen.main?.frame)!
        let y = frame.size.height - self.y
        return NSPoint(x: self.x, y: y)
    }
}
