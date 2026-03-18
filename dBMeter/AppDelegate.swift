import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let audioMeter = AudioMeter()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var statusUpdateTimer: Timer?
    private var isUpdatingStatusItem = false
    private var lastRenderedTitle: String = ""
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        setupPopover()
        setupStatusItem()
        startStatusUpdateTimer()
        audioMeter.startMonitoring()
        updateStatusItemAppearance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = nil
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(audioMeter)
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        button.wantsLayer = false
        button.title = "-- dBFS"
    }

    private func startStatusUpdateTimer() {
        statusUpdateTimer?.invalidate()
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.updateStatusItemAppearance()
        }
    }

    private func updateStatusItemAppearance() {
        guard !isUpdatingStatusItem else { return }
        isUpdatingStatusItem = true
        defer { isUpdatingStatusItem = false }

        guard let button = statusItem?.button else { return }

        let backgroundColor: NSColor

        if audioMeter.isFlashVisible {
            switch audioMeter.alertLevel {
            case .none:
                backgroundColor = .clear
            case .yellow:
                backgroundColor = .systemYellow
            case .red:
                backgroundColor = .systemRed
            }
        } else {
            backgroundColor = .clear
        }

        let title = "\(audioMeter.menuBarTitle)"
        let stateChanged = title != lastRenderedTitle

        if stateChanged {
            // Use the native menu bar text rendering path.
            button.contentTintColor = nil
            button.title = title
            lastRenderedTitle = title
        }

        if colorsEqual(backgroundColor, .clear) {
            // Explicitly clear any previously painted layer background.
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.wantsLayer = false
        } else {
            button.wantsLayer = true
            button.layer?.masksToBounds = true
            button.layer?.cornerRadius = max(6, button.bounds.height / 2)
            button.layer?.backgroundColor = backgroundColor.cgColor
        }
    }

    private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        return left == right
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        if event.type == .leftMouseUp {
            audioMeter.toggleRunning()
            return
        }

        guard event.type == .rightMouseUp else { return }

        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        _ = notification
        installOutsideClickDismissMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        _ = notification
        removeOutsideClickDismissMonitors()
    }

    private func installOutsideClickDismissMonitors() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfClickIsOutside()
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopoverIfClickIsOutside()
            }
        }
    }

    private func removeOutsideClickDismissMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func closePopoverIfClickIsOutside() {
        guard popover.isShown else { return }
        guard let popoverWindow = popover.contentViewController?.view.window else {
            popover.performClose(nil)
            return
        }

        let clickLocation = NSEvent.mouseLocation
        if popoverWindow.frame.contains(clickLocation) {
            return
        }

        popover.performClose(nil)
    }
}
