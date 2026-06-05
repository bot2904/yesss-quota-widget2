import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = TrayViewModel()

    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var eventMonitor: Any?
    private var refreshTimer: Timer?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureStatusItem()
        configurePopover()
        bindViewModel()

        updateStatusItemTitle()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self {
                Task { @MainActor in
                    self.viewModel.refreshNow()
                }
            }
        }

        scheduleRefreshTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        refreshTimer?.invalidate()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.title = "--"
        item.button?.toolTip = "YESSS quota"
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 430)
        popover.contentViewController = NSHostingController(rootView: TrayPopoverView(viewModel: viewModel))
    }

    private func bindViewModel() {
        viewModel.$snapshot
            .combineLatest(viewModel.$isRefreshing)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem?.button else {
            return
        }
        button.title = viewModel.menuBarTitle
        button.toolTip = viewModel.statusText
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        let shouldShowContextMenu = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if shouldShowContextMenu {
            showContextMenu()
            return
        }

        togglePopover(sender)
    }

    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
            return
        }

        guard let button = statusItem?.button else {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startEventMonitor()
    }

    private func showContextMenu() {
        closePopover(nil)
        guard let statusItem else {
            return
        }

        guard let button = statusItem.button else {
            return
        }

        let menu = buildContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let refreshNowItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNowFromMenu(_:)), keyEquivalent: "")
        refreshNowItem.target = self
        refreshNowItem.isEnabled = !viewModel.isRefreshing
        menu.addItem(refreshNowItem)

        let settingsWindowItem = NSMenuItem(title: "Open Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsWindowItem.target = self
        menu.addItem(settingsWindowItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc
    private func refreshNowFromMenu(_ sender: AnyObject?) {
        viewModel.refreshNow()
    }

    @objc
    private func openSettingsFromMenu(_ sender: AnyObject?) {
        showSettingsWindow()
    }

    @objc
    private func quitFromMenu(_ sender: AnyObject?) {
        NSApplication.shared.terminate(nil)
    }

    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(viewModel: viewModel) { [weak self] in
            self?.viewModel.refreshNow()
        } onRefreshIntervalChanged: { [weak self] in
            self?.scheduleRefreshTimer()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YESSS Settings"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()

        let interval = AppConfig.periodicRefreshSeconds
        guard interval > 0 else {
            refreshTimer = nil
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            if let self {
                Task { @MainActor in
                    self.viewModel.refreshNow()
                }
            }
        }

        refreshTimer?.tolerance = min(interval * 0.15, 30)
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        guard eventMonitor == nil else {
            return
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self {
                Task { @MainActor in
                    self.closePopover(nil)
                }
            }
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
