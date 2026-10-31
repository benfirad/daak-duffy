import SwiftUI
import Combine

@MainActor
final class DuffyAppDelegate: NSObject, NSApplicationDelegate {
    let monitor = DuffyMonitor()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var homeWindow: NSWindow?
    private var consoleWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchAgent + elle açma iki kopya üretmesin. Aynı anda başlayan iki kopya birbirini
        // NSRunningApplication listesinde göremeyebiliyor; dosya kilidi bu yarışı kapatır.
        // İkinci kopya başarıyla çıkar, böylece KeepAlive onu yeniden başlatmaz.
        if !Self.acquireInstanceLock() {
            // Uygulamayı yeniden açmak "pencereyi göster" demek; çalışan kopyaya haber ver
            DistributedNotificationCenter.default().postNotificationName(Self.showNote, object: nil, deliverImmediately: true)
            exit(0)
        }
        DistributedNotificationCenter.default().addObserver(forName: Self.showNote, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openHome() }
        }

        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let appIcon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = appIcon
        }

        Self.log("başladı, pid \(ProcessInfo.processInfo.processIdentifier), ayar: \(AppConfig.path)")
        monitor.openConsoleCallback = { [weak self] in self?.openConsole() }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 410, height: 740)
        popover.contentViewController = NSHostingController(rootView: HomeView().environmentObject(monitor))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = Self.makeMenuBarDuckImage()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "DAAK Duffy · Sol tık: ajanlar · Sağ tık: konsol"
        }

        // Onay bekleyen işlem varsa menü çubuğunda sayısı görünsün
        monitor.$tasks
            .map { $0.filter { $0.status == "awaiting_approval" }.count }
            .removeDuplicates()
            .sink { [weak self] n in
                self?.statusItem?.button?.title = n > 0 ? " \(n)" : ""
                NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
            }
            .store(in: &bag)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.openHome()
        }
    }

    private static let showNote = Notification.Name("app.daakduffy.menu.show")
    private static var lockFD: Int32 = -1

    private static func log(_ s: String) {
        FileHandle.standardError.write("[\(Fmt.clock(Date()))] \(s)\n".data(using: .utf8)!)
    }

    private static func acquireInstanceLock() -> Bool {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("app.daakduffy.menu.lock")
        lockFD = open(path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { return true }
        // Kilit süreç kapanınca çekirdek tarafından bırakılır
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0
    }

    private static func makeMenuBarDuckImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 8.8, width: 6.8, height: 6.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.8, y: 14.5, width: 2.2, height: 2.6)).fill()
            NSBezierPath(roundedRect: NSRect(x: 13.0, y: 10.6, width: 3.8, height: 2.3), xRadius: 1.1, yRadius: 1.1).fill()
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 2.0, y: 8.2))
            body.curve(to: NSPoint(x: 13.4, y: 6.8), controlPoint1: NSPoint(x: 4.5, y: 10.2), controlPoint2: NSPoint(x: 10.5, y: 9.8))
            body.curve(to: NSPoint(x: 8.2, y: 2.2), controlPoint1: NSPoint(x: 14.2, y: 4.0), controlPoint2: NSPoint(x: 11.8, y: 2.2))
            body.curve(to: NSPoint(x: 1.8, y: 5.5), controlPoint1: NSPoint(x: 4.5, y: 2.2), controlPoint2: NSPoint(x: 2.2, y: 3.4))
            body.close()
            body.fill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
            NSBezierPath(ovalIn: NSRect(x: 10.8, y: 11.7, width: 1.4, height: 1.4)).fill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
            return true
        }
        img.isTemplate = true
        return img
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openHome()
        return true
    }

    func openHome() {
        Self.log("ana pencere açılıyor (mevcut: \(homeWindow != nil))")
        if let w = homeWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DAAK Duffy"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.062, alpha: 1.0)
        window.contentViewController = NSHostingController(rootView: HomeView().environmentObject(monitor))
        window.setFrameAutosaveName("DuffyHome")
        if !window.setFrameUsingName("DuffyHome") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        homeWindow = window
    }

    func openConsole() {
        if popover.isShown { popover.performClose(nil) }
        if let w = consoleWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DAAK Duffy Konsol"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: ConsoleView().environmentObject(monitor))
        window.setFrameAutosaveName("DuffyConsole")
        if !window.setFrameUsingName("DuffyConsole") { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        consoleWindow = window
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            monitor.openConsole(monitor.pendingApprovals.isEmpty ? nil : .approvals)
            return
        }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        Task { await monitor.refresh() }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct DAAKDuffyApp: App {
    @NSApplicationDelegateAdaptor(DuffyAppDelegate.self) private var appDelegate

    init() {
        // Pencereler her açılışta koddan kurulur; macOS'un pencere geri yükleme özelliği gereksiz.
        // Üstelik art arda çöküşten sonra "pencereleri geri yükle?" diyaloğu açılışı kilitliyordu.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true, "NSQuitAlwaysKeepsWindows": false])
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
