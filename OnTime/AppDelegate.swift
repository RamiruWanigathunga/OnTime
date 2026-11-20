import AppKit
import AppIntents
import SwiftUI
import Combine
import Carbon
import ServiceManagement
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
  /// Mutable stretch-gesture flags shared between Esc monitors and the tracking loop.
  private final class StretchCancelState: @unchecked Sendable {
    var committed = false
    var cancelled = false
    var animatedDismissStarted = false
  }

  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private let model = OnTimeModel.shared
  private var cancellables = Set<AnyCancellable>()
  private var hotKeyRef: EventHotKeyRef?
  private var pauseResumeHotKeyRef: EventHotKeyRef?
  private var trashHotKeyRef: EventHotKeyRef?
  private var startPomodoroHotKeyRef: EventHotKeyRef?
  private var startStopwatchHotKeyRef: EventHotKeyRef?
  private var hotKeyHandlerRef: EventHandlerRef?
  private var currentOpenHotkey: Hotkey?
  private var currentPauseResumeHotkey: Hotkey?
  private var currentClearHotkey: Hotkey?
  private var currentStartPomodoroHotkey: Hotkey?
  private var currentStartStopwatchHotkey: Hotkey?
  private var hotkeyDefaultsObserver: NSObjectProtocol?
  private var hotkeyChangeObserver: NSObjectProtocol?
  private var contextMenu: NSMenu?
  private var openItem: NSMenuItem?
  private var stopwatchItem: NSMenuItem?
  private var pauseItem: NSMenuItem?
  private var clearItem: NSMenuItem?
  private var repeatItem: NSMenuItem?
  private var pomodoroItem: NSMenuItem?
  private var eventMonitor: Any?
  private var keyMonitor: Any?
  private var lastStatusItemState: StatusItemState?
  private var isStatusItemHovered = false
  private var statusItemTrackingArea: NSTrackingArea?
  private let stretchOverlay = MenuBarStretchOverlay()
  private var stretchPressActive = false
  private var statusItemHitView: StatusItemHitView?

  private struct StatusItemState: Equatable {
    let isRunning: Bool
    let displayText: String
    let tooltip: String?
    let iconSize: NSSize
    let icon: String
    let style: String
    let fontStyle: String
    let progress: Double
    let isHovered: Bool
  }

  private func currentMenuBarStyle() -> MenuBarStyle {
    let raw = UserDefaults.standard.string(forKey: OnTimeSettingsKeys.menuBarStyle) ?? ""
    // Retired "compactBadge" falls back to classic.
    return MenuBarStyle(rawValue: raw) ?? .default
  }

  /// Ring styles don’t apply to stopwatch (no countdown progress).
  private func resolvedMenuBarStyle(from style: MenuBarStyle) -> MenuBarStyle {
    if model.isRunning, model.mode == .stopwatch {
      return style.styleForStopwatch()
    }
    return style
  }

  private func currentMenuBarFontStyle() -> MenuBarFontStyle {
    let raw = UserDefaults.standard.string(forKey: OnTimeSettingsKeys.menuBarFontStyle) ?? ""
    return MenuBarFontStyle(rawValue: raw) ?? .default
  }

  private func currentMenuBarIcon() -> MenuBarIcon {
    MenuBarIcon.current()
  }

  private func currentStatusItemState() -> StatusItemState {
    StatusItemState(
      isRunning: model.isRunning,
      displayText: model.isRunning ? model.formattedStatusText : "",
      tooltip: model.isRunning ? model.endsAtSublabel : nil,
      iconSize: menuBarIconSize(),
      icon: currentMenuBarIcon().rawValue,
      style: currentMenuBarStyle().rawValue,
      fontStyle: currentMenuBarFontStyle().rawValue,
      progress: model.progressFraction,
      isHovered: isStatusItemHovered
    )
  }

  private func statusBarImage() -> NSImage {
    currentMenuBarIcon().templateImage(size: menuBarIconSize())
  }

  private static let popoverWillShowNotification = Notification.Name("OnTimePopoverWillShow")

  private var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Host-based unit tests inject into this process. Skip menu-bar/UI setup so XCTest
    // can finish without a sticky LSUIElement run loop or login prompts.
    if isRunningUnitTests {
      return
    }

    NSApp.setActivationPolicy(.accessory)
    #if DEBUG
    terminateOtherInstances()
    #endif
    // Touch Sparkle early so SPUStandardUpdaterController starts (automatic checks off).
    _ = OnTimeUpdater.shared
    migrateNotificationRepeatDefault()
    DisplayPrecision.migrateIfNeeded()
    AudioDefaults.migrateNotificationVolumeIfNeeded()
    configurePopover()
    configureStatusItem()
    bindModel()
    updateStatusItem()
    configureHotkeys()
    configureNotificationCategories()
    observeSleepWake()
    configureURLHandling()
    wireSessionLogger()
    // Once at launch is enough; refreshing on every activation spams LinkDaemon
    // (Code=5) for an accessory app and does extra IPC for no UI gain.
    refreshAppShortcutsRegistration()
    OnTimeLogger.shared.log(event: "app_start")
    UNUserNotificationCenter.current().delegate = self
    DispatchQueue.main.async { [weak self] in
      self?.promptForLaunchAtLoginIfNeeded()
    }
  }

  /// Settings → About → Check for Updates…
  func checkForUpdatesFromSettings() {
    OnTimeUpdater.shared.checkForUpdates()
  }

  /// Re-publish App Shortcut phrases so Shortcuts/Siri pick up this signed build.
  private func refreshAppShortcutsRegistration() {
    OnTimeShortcutsProvider.updateAppShortcutParameters()
  }

  private func wireSessionLogger() {
    model.eventLogger = { event, fields in
      OnTimeLogger.shared.log(event: event, fields: fields)
    }
  }

  private func configureURLHandling() {
    let manager = NSAppleEventManager.shared()
    manager.setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  @objc private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: urlString),
      let action = OnTimeURLHandler.parse(url)
    else { return }
    _ = OnTimeURLHandler.perform(action, on: model)
  }

  private func terminateOtherInstances() {
    guard let bundleId = Bundle.main.bundleIdentifier else { return }
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    let current = NSRunningApplication.current
    for app in runningApps where app.processIdentifier != current.processIdentifier {
      app.terminate()
    }
  }

  private func promptForLaunchAtLoginIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: OnTimeSettingsKeys.didPromptLoginItem) else { return }
    defaults.set(true, forKey: OnTimeSettingsKeys.didPromptLoginItem)

    if #available(macOS 13.0, *), SMAppService.mainApp.status == .enabled {
      return
    }

    let alert = NSAlert()
    alert.messageText = "Launch OnTime at login?"
    alert.informativeText = "This can be changed later in Settings."
    alert.addButton(withTitle: "Add")
    alert.addButton(withTitle: "Not now")
    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }
    if #available(macOS 13.0, *) {
      try? SMAppService.mainApp.register()
    }
  }

  private func migrateNotificationRepeatDefault() {
    let defaults = UserDefaults.standard
    guard defaults.integer(forKey: OnTimeSettingsKeys.repeatCountMigrationVersion) < 1 else {
      return
    }

    let existingInstallationKeys = [
      OnTimeSettingsKeys.tone,
      OnTimeSettingsKeys.volume,
      OnTimeSettingsKeys.defaultUnit,
      OnTimeSettingsKeys.openHotkey,
      OnTimeSettingsKeys.pauseResumeHotkey,
      OnTimeSettingsKeys.clearHotkey,
      OnTimeSettingsKeys.didPromptLoginItem,
      OnTimeSettingsKeys.showNotifications,
      OnTimeSettingsKeys.menuBarIconSize,
      OnTimeSettingsKeys.menuButtonSize,
      OnTimeSettingsKeys.menuButtonBrightness,
    ]
    let isExistingInstallation = existingInstallationKeys.contains {
      defaults.object(forKey: $0) != nil
    }

    if isExistingInstallation, defaults.object(forKey: OnTimeSettingsKeys.repeatCount) == nil {
      defaults.set(NotificationRepeatOption.ten.rawValue, forKey: OnTimeSettingsKeys.repeatCount)
    }
    defaults.set(1, forKey: OnTimeSettingsKeys.repeatCountMigrationVersion)
  }

  private func configurePopover() {
    let view = OnTimeMenuView()
      .environmentObject(model)
      .environment(\.menuDismiss, MenuDismissAction { [weak self] in
        self?.popover.performClose(nil)
      })
    popover.contentViewController = NSHostingController(rootView: view)
    // Keep applicationDefined so global monitors own dismiss; animate open/close.
    popover.behavior = .applicationDefined
    popover.animates = true
    popover.delegate = self
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else { return }
    // Keep button for drawing image/title; interaction goes through a transparent hit view
    // so mouseDown/drag tracking actually runs on the menu bar item.
    button.target = nil
    button.action = nil
    button.sendAction(on: [])

    let hitView: StatusItemHitView
    if let existing = statusItemHitView {
      hitView = existing
      hitView.frame = button.bounds
    } else {
      hitView = StatusItemHitView(frame: button.bounds)
      hitView.autoresizingMask = [.width, .height]
      statusItemHitView = hitView
      button.addSubview(hitView)
    }
    hitView.onLeftMouseDown = { [weak self, weak button] event in
      guard let self, let button else { return }
      if self.isStretchToSetEnabled {
        self.runStretchOrClickTracking(from: button, initialEvent: event)
      } else {
        self.runClassicClickTracking(from: button)
      }
    }
    hitView.onRightMouseUp = { [weak self] _ in
      self?.stretchOverlay.dismiss()
      self?.stretchPressActive = false
      self?.showContextMenu()
    }

    installStatusItemTrackingArea(on: button)
  }

  private var isStretchToSetEnabled: Bool {
    if UserDefaults.standard.object(forKey: OnTimeSettingsKeys.stretchToSetTimer) == nil {
      return StretchTimerDefaults.isEnabled
    }
    return UserDefaults.standard.bool(forKey: OnTimeSettingsKeys.stretchToSetTimer)
  }

  private func installStatusItemTrackingArea(on button: NSStatusBarButton) {
    if let statusItemTrackingArea {
      button.removeTrackingArea(statusItemTrackingArea)
    }
    let area = NSTrackingArea(
      rect: button.bounds,
      options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    button.addTrackingArea(area)
    statusItemTrackingArea = area
  }

  // NSTrackingArea dispatches ObjC `mouseEntered:` / `mouseExited:`. A plain
  // `@objc func mouseEntered(with:)` on NSObject exports as `mouseEnteredWithEvent:`
  // and crashes with unrecognized selector — pin the selector names explicitly.
  @objc(mouseEntered:)
  func statusItemMouseEntered(_ event: NSEvent) {
    isStatusItemHovered = true
    updateStatusItem()
  }

  @objc(mouseExited:)
  func statusItemMouseExited(_ event: NSEvent) {
    isStatusItemHovered = false
    updateStatusItem()
  }

  private func bindModel() {
    Publishers.Merge5(
      model.$remaining.map { _ in () },
      model.$elapsed.map { _ in () },
      model.$isRunning.map { _ in () },
      model.$pomodoroLabel.map { _ in () },
      model.$pomodoroCompleted.map { _ in () }
    )
      .sink { [weak self] _ in
        DispatchQueue.main.async {
          self?.updateStatusItem()
        }
      }
      .store(in: &cancellables)
  }

  private func updateStatusItem() {
    guard let button = statusItem.button else { return }
    let state = currentStatusItemState()
    if state == lastStatusItemState {
      return
    }
    lastStatusItemState = state
    let style = resolvedMenuBarStyle(
      from: MenuBarStyle(rawValue: state.style) ?? .default
    )
    let fontStyle = MenuBarFontStyle(rawValue: state.fontStyle) ?? .default
    let font = fontStyle.menuBarFont()
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let size = state.iconSize

    switch style {
    case .classic:
      if state.isRunning {
        button.attributedTitle = NSAttributedString(string: state.displayText, attributes: attributes)
        button.image = nil
        button.toolTip = state.tooltip
      } else {
        button.attributedTitle = NSAttributedString(string: "")
        button.image = statusBarImage()
        button.toolTip = nil
      }

    case .ringAndTime:
      if state.isRunning {
        button.image = MenuBarRingImage.make(progress: state.progress, size: size)
        button.attributedTitle = NSAttributedString(string: " " + state.displayText, attributes: attributes)
        button.toolTip = state.tooltip
      } else {
        button.attributedTitle = NSAttributedString(string: "")
        button.image = statusBarImage()
        button.toolTip = nil
      }

    case .ringOnly:
      if state.isRunning {
        button.image = MenuBarRingImage.make(progress: state.progress, size: size)
        if state.isHovered {
          button.attributedTitle = NSAttributedString(string: " " + state.displayText, attributes: attributes)
        } else {
          button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = state.tooltip ?? state.displayText
      } else {
        button.attributedTitle = NSAttributedString(string: "")
        button.image = statusBarImage()
        button.toolTip = nil
      }

    case .iconOnly:
      if state.isRunning {
        button.image = statusBarImage()
        if state.isHovered {
          button.attributedTitle = NSAttributedString(string: " " + state.displayText, attributes: attributes)
        } else {
          button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = state.tooltip ?? state.displayText
      } else {
        button.attributedTitle = NSAttributedString(string: "")
        button.image = statusBarImage()
        button.toolTip = nil
      }
    }
    updateContextMenuItems()
  }

  /// Classic click-to-open: consume the press and toggle on mouse-up without stretch.
  private func runClassicClickTracking(from button: NSStatusBarButton) {
    guard button.window != nil else {
      togglePopover(button)
      return
    }
    let mask: NSEvent.EventTypeMask = [.leftMouseUp, .leftMouseDragged]
    // Status-item windows only deliver follow-up mouse events in the tracking run-loop mode.
    while let next = NSApp.nextEvent(
      matching: mask,
      until: .distantFuture,
      inMode: .eventTracking,
      dequeue: true
    ) {
      if next.type == .leftMouseUp {
        togglePopover(button)
        return
      }
    }
  }

  /// Drag below threshold → stretch overlay; release without drag → popover.
  private func runStretchOrClickTracking(from button: NSStatusBarButton, initialEvent: NSEvent) {
    guard let window = button.window else {
      togglePopover(button)
      return
    }

    stretchPressActive = true
    // Shared across Esc monitors (any thread) and the main-thread tracking loop.
    let cancelState = StretchCancelState()
    defer {
      stretchPressActive = false
      stretchOverlay.onEscape = nil
      if !cancelState.committed, !cancelState.animatedDismissStarted, stretchOverlay.isVisible {
        stretchOverlay.dismiss()
      }
    }

    let buttonRectInWindow = button.convert(button.bounds, to: nil)
    let screenRect = window.convertToScreen(buttonRectInWindow)
    let anchorInScreen = NSPoint(x: screenRect.midX, y: screenRect.minY)

    var stretchActivated = false
    var pendingDuration: TimeInterval?
    _ = initialEvent

    let mask: NSEvent.EventTypeMask = [
      .leftMouseUp, .leftMouseDragged, .flagsChanged, .keyDown,
    ]

    // Status-item mouseDown often has a spurious `leftMouseUp` already queued (rawValue 2)
    // while `pressedMouseButtons` still reports the button down. Trust the button bit, not
    // the event type, and poll cursor position so stretch works even without mouseDragged.
    var sawButtonDown = (NSEvent.pressedMouseButtons & (1 << 0)) != 0
    // If mouseDown ran after the physical release (fully synthetic click), open the popover
    // after a short grace — never stretch from a stale cursor position.
    let trackingStarted = Date()

    // Esc often goes to the frontmost app, not our non-key status item. Local + global
    // monitors catch it; the stretch HUD also becomes key when shown.
    // Mark cancelled synchronously so the tracking loop stops immediately; UI work is a
    // MainActor method hop (no stored/non-Sendable function value passed to assumeIsolated).
    let cancelStretch: @Sendable () -> Void = { [weak self] in
      guard !cancelState.cancelled else { return }
      if cancelState.committed { return }
      cancelState.cancelled = true
      Task { @MainActor in
        self?.finishStretchCancel(state: cancelState)
      }
    }
    stretchOverlay.onEscape = cancelStretch

    let localEsc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        cancelStretch()
        return nil
      }
      return event
    }
    let globalEsc = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 53 {
        cancelStretch()
      }
    }
    defer {
      if let localEsc { NSEvent.removeMonitor(localEsc) }
      if let globalEsc { NSEvent.removeMonitor(globalEsc) }
    }

    // Poll mouse location on a short timeout. Status-item windows (and some synthetic
    // drags) often never enqueue `leftMouseDragged`, so a blocking nextEvent loop would
    // only see mouseUp and treat every gesture as a click.
    while true {
      let next = NSApp.nextEvent(
        matching: mask,
        until: Date().addingTimeInterval(1.0 / 60.0),
        inMode: .eventTracking,
        dequeue: true
      )

      if let next, next.type == .keyDown, next.keyCode == 53 {  // Esc
        cancelStretch()
      }
      // Key events often never enqueue during status-item mouse tracking; poll hardware state.
      if CGEventSource.keyState(.combinedSessionState, key: 53) {
        cancelStretch()
      }

      let cursor = NSEvent.mouseLocation
      let deltaY = max(0, anchorInScreen.y - cursor.y)
      let optionHeld = (next?.modifierFlags ?? NSEvent.modifierFlags).contains(.option)
        || NSEvent.modifierFlags.contains(.option)
      let buttons = NSEvent.pressedMouseButtons
      let buttonDown = (buttons & (1 << 0)) != 0
      if buttonDown {
        sawButtonDown = true
      }

      let timedOutWithoutDown =
        !sawButtonDown && Date().timeIntervalSince(trackingStarted) > 0.12
      if timedOutWithoutDown {
        togglePopover(button)
        return
      }

      // Only stretch while the button is actually held — avoids committing a huge duration
      // from a leftover cursor position when mouseDown arrives after mouseUp.
      if !cancelState.cancelled, buttonDown, !stretchActivated,
        deltaY >= StretchTimerMapper.activationThreshold
      {
        stretchActivated = true
        if popover.isShown {
          popover.performClose(nil)
        }
        let screen =
          NSScreen.screens.first { NSMouseInRect(anchorInScreen, $0.frame, false) }
          ?? window.screen
          ?? NSScreen.main
        if let screen {
          stretchOverlay.show(anchorInScreen: anchorInScreen, on: screen)
        }
      }

      if !cancelState.cancelled, buttonDown, stretchActivated {
        pendingDuration = stretchOverlay.update(
          cursorInScreen: cursor,
          isOptionHeld: optionHeld
        )
      }

      guard sawButtonDown, !buttonDown else { continue }

      if cancelState.cancelled {
        // fade already started by cancelStretch; do not double-dismiss
        return
      }

      if stretchActivated {
        if let pendingDuration, pendingDuration > 0 {
          commitStretchedCountdown(duration: pendingDuration, announcingOn: button)
          cancelState.committed = true
          cancelState.animatedDismissStarted = true
          stretchOverlay.settleSuccess()
        } else {
          cancelState.animatedDismissStarted = true
          stretchOverlay.fadeCancel()
        }
      } else {
        togglePopover(button)
      }
      return
    }
  }

  private func finishStretchCancel(state: StretchCancelState) {
    if stretchOverlay.dismissPhase == .settling {
      return
    }
    if stretchOverlay.isVisible {
      state.animatedDismissStarted = true
      stretchOverlay.fadeCancel()
    } else {
      stretchOverlay.dismiss()
    }
  }

  private func commitStretchedCountdown(duration: TimeInterval, announcingOn button: NSStatusBarButton)
  {
    model.startStretchedCountdown(duration: duration)
    let announcement: String
    if duration >= 60 {
      let mins = Int((duration / 60).rounded())
      announcement = mins == 1 ? "Started 1 minute timer" : "Started \(mins) minute timer"
    } else {
      let secs = Int(duration.rounded())
      announcement = secs == 1 ? "Started 1 second timer" : "Started \(secs) second timer"
    }
    NSAccessibility.post(
      element: button,
      notification: .announcementRequested,
      userInfo: [
        .announcement: announcement,
        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
      ]
    )
  }

  private func togglePopover(_ sender: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(sender)
    } else {
      showPopover(relativeTo: sender)
    }
  }

  private func showPopoverFromNotification() {
    guard !popover.isShown, let button = statusItem.button else { return }
    showPopover(relativeTo: button)
  }

  private func showPopover(relativeTo button: NSStatusBarButton) {
    NotificationCenter.default.post(name: Self.popoverWillShowNotification, object: nil)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    // Key the popover window so typing lands in the field immediately.
    popover.contentViewController?.view.window?.makeKey()
    startEventMonitors()
  }

  private func togglePopoverFromHotKey() {
    guard let button = statusItem.button else { return }
    togglePopover(button)
  }

  private func trashFromHotKey() {
    model.stop()
    popover.performClose(nil)
  }

  private func togglePauseResumeFromHotKey() {
    guard model.isRunning else { return }
    if model.isPaused {
      model.resume()
    } else {
      model.pause()
    }
  }

  private func showContextMenu() {
    popover.performClose(nil)
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    menu.showsStateColumn = false
    let openItem = NSMenuItem(title: "Open", action: #selector(openTimerFromMenu), keyEquivalent: "t")
    openItem.target = self
    menu.addItem(openItem)
    self.openItem = openItem

    let startStopwatchItem = NSMenuItem(title: "Stopwatch", action: #selector(startStopwatchFromMenu), keyEquivalent: "")
    startStopwatchItem.target = self
    menu.addItem(startStopwatchItem)
    stopwatchItem = startStopwatchItem

    let pomodoroItem = NSMenuItem(
      title: "Pomodoro", action: #selector(startPomodoroFromMenu), keyEquivalent: ""
    )
    pomodoroItem.target = self
    menu.addItem(pomodoroItem)
    self.pomodoroItem = pomodoroItem

    let newPauseItem = NSMenuItem(title: "Pause", action: #selector(pauseTimerFromMenu), keyEquivalent: "")
    newPauseItem.target = self
    menu.addItem(newPauseItem)
    pauseItem = newPauseItem

    let stopItem = NSMenuItem(title: "Clear", action: #selector(stopTimerFromMenu), keyEquivalent: "x")
    stopItem.target = self
    menu.addItem(stopItem)
    clearItem = stopItem

    if model.canRepeat {
      let repeatItem = NSMenuItem(title: "Repeat", action: #selector(repeatTimerFromMenu), keyEquivalent: "r")
      repeatItem.target = self
      menu.addItem(repeatItem)
      self.repeatItem = repeatItem
    }
    menu.addItem(.separator())

    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
    settingsItem.keyEquivalentModifierMask = [.command]
    settingsItem.target = self
    menu.addItem(settingsItem)

    let aboutItem = NSMenuItem(
      title: "About OnTime",
      action: #selector(openAboutFromMenu),
      keyEquivalent: ""
    )
    aboutItem.target = self
    menu.addItem(aboutItem)

    menu.addItem(.separator())
    let quitItem = NSMenuItem(title: "Quit OnTime", action: #selector(quitApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    contextMenu = menu
    updateContextMenuItems()
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  private func updateContextMenuItems() {
    guard let menu = contextMenu else { return }
    stopwatchItem?.isEnabled = true
    let pauseAllowed = !model.isTimeOfDayCountdown
    pauseItem?.isEnabled = model.isRunning && !model.isFinished && (model.isPaused || pauseAllowed)
    clearItem?.isEnabled = model.isRunning
    applyHotkeyHint(for: .open, to: openItem)
    applyHotkeyHint(for: .pauseResume, to: pauseItem)
    applyHotkeyHint(for: .clear, to: clearItem)
    applyHotkeyHint(for: .startStopwatch, to: stopwatchItem)
    pomodoroItem?.title = "Pomodoro"
    applyHotkeyHint(for: .startPomodoro, to: pomodoroItem)

    if model.isPaused && !model.isFinished {
      pauseItem?.title = "Restart"
      pauseItem?.action = #selector(restartTimerFromMenu)
    } else {
      pauseItem?.title = "Pause"
      pauseItem?.action = #selector(pauseTimerFromMenu)
    }

    if model.canRepeat {
      if repeatItem == nil {
        let item = NSMenuItem(title: "Repeat", action: #selector(repeatTimerFromMenu), keyEquivalent: "r")
        item.target = self
        if let clearItem, menu.index(of: clearItem) != -1 {
          menu.insertItem(item, at: menu.index(of: clearItem) + 1)
        } else {
          menu.addItem(item)
        }
        repeatItem = item
      }
    } else if let repeatItem {
      menu.removeItem(repeatItem)
      self.repeatItem = nil
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    if menu == contextMenu {
      contextMenu = nil
      openItem = nil
      stopwatchItem = nil
      pauseItem = nil
      clearItem = nil
      repeatItem = nil
      pomodoroItem = nil
    }
  }

  func popoverDidClose(_ notification: Notification) {
    stopEventMonitors()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  @objc private func openTimerFromMenu() {
    togglePopoverFromHotKey()
  }

  @objc private func startStopwatchFromMenu() {
    model.startStopwatch()
  }

  @objc private func pauseTimerFromMenu() {
    model.pause()
  }

  @objc private func restartTimerFromMenu() {
    model.resume()
  }

  @objc private func stopTimerFromMenu() {
    model.stop()
    popover.performClose(nil)
  }

  @objc private func repeatTimerFromMenu() {
    if model.repeatLastInput() {
      popover.performClose(nil)
    }
  }

  @objc private func startPomodoroFromMenu() {
    model.startPomodoro()
  }

  @objc private func openSettingsFromMenu() {
    openSettingsClosingPopover()
  }

  private var aboutPanelCloseObserver: NSObjectProtocol?

  @objc private func openAboutFromMenu() {
    // Accessory / LSUIElement apps often hide the standard About panel until a
    // real window exists (e.g. Settings). Temporarily become a regular app.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: Self.aboutCredits()
    ])
    observeAboutPanelCloseToRestoreAccessoryPolicy()
  }

  private func isStandardAboutPanel(_ window: NSWindow) -> Bool {
    if window.frameAutosaveName == "NSAboutPanel" { return true }
    return window.title.localizedCaseInsensitiveContains("About")
  }

  private func observeAboutPanelCloseToRestoreAccessoryPolicy() {
    if let aboutPanelCloseObserver {
      NotificationCenter.default.removeObserver(aboutPanelCloseObserver)
      self.aboutPanelCloseObserver = nil
    }
    aboutPanelCloseObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self, let window = notification.object as? NSWindow else { return }
      Task { @MainActor in
        guard self.isStandardAboutPanel(window) else { return }
        self.restoreAccessoryActivationPolicyAfterAbout()
      }
    }
  }

  private func restoreAccessoryActivationPolicyAfterAbout() {
    if let aboutPanelCloseObserver {
      NotificationCenter.default.removeObserver(aboutPanelCloseObserver)
      self.aboutPanelCloseObserver = nil
    }
    NSApp.setActivationPolicy(.accessory)
  }

  private static func aboutCredits() -> NSAttributedString {
    let items: [(String, String)] = [
      ("Upstream Tock", "https://github.com/edelstone/tock"),
      ("TomatoBar", "https://github.com/ivoronin/TomatoBar"),
      ("License", "https://polyformproject.org/licenses/shield/1.0.0")
    ]
    let result = NSMutableAttributedString()
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineSpacing = 4
    let font = NSFont.systemFont(ofSize: 14, weight: .regular)
    for (index, item) in items.enumerated() {
      let (title, urlString) = item
      let attributes: [NSAttributedString.Key: Any] = [
        .link: urlString,
        .font: font,
        .paragraphStyle: paragraphStyle
      ]
      result.append(NSAttributedString(string: title, attributes: attributes))
      if index < items.count - 1 {
        result.append(NSAttributedString(string: "\n"))
      }
    }
    result.insert(NSAttributedString(string: "\n"), at: 0)
    result.append(NSAttributedString(string: "\n"))
    return result
  }

  func openSettingsFromCommand() {
    openSettingsClosingPopover()
  }

  /// Closes the menu-bar popover (no animation) then shows Settings.
  /// Animated popover teardown resigns the Settings panel and auto-dismisses it.
  func openSettingsClosingPopover() {
    if popover.isShown {
      let animated = popover.animates
      popover.animates = false
      popover.performClose(nil)
      popover.animates = animated
    }
    SettingsWindowController.shared.show()
  }

  private func configureHotkeys() {
    #if canImport(KeyboardShortcuts)
    Hotkey.migrateRecorderDefaultsIfNeeded()
    #endif
    Hotkey.seedDefaultsIfNeeded()
    #if canImport(KeyboardShortcuts)
    // Sync recorder display storage, then leave global capture to Carbon below.
    Hotkey.updateRecorderUI(Hotkey.load(for: .open), name: .openRecorder)
    Hotkey.updateRecorderUI(Hotkey.load(for: .pauseResume), name: .pauseResumeRecorder)
    Hotkey.updateRecorderUI(Hotkey.load(for: .clear), name: .clearRecorder)
    Hotkey.updateRecorderUI(Hotkey.load(for: .startPomodoro), name: .startPomodoroRecorder)
    Hotkey.updateRecorderUI(Hotkey.load(for: .startStopwatch), name: .startStopwatchRecorder)
    Hotkey.disableRecorderGlobalCapture()
    #endif
    reloadHotkeysFromDefaults()
    observeHotkeyDefaults()
    observeHotkeyChanges()
  }

  private func configureNotificationCategories() {
    let clearAction = UNNotificationAction(
      identifier: NotificationIdentifiers.clearAction,
      title: "Clear"
    )
    let repeatAction = UNNotificationAction(
      identifier: NotificationIdentifiers.repeatAction,
      title: "Repeat"
    )
    let stopPomodoroAction = UNNotificationAction(
      identifier: NotificationIdentifiers.stopPomodoroAction,
      title: "Stop Pomodoro"
    )
    let skipBreakAction = UNNotificationAction(
      identifier: NotificationIdentifiers.skipBreakAction,
      title: "Skip Phase"
    )
    let pauseAction = UNNotificationAction(
      identifier: NotificationIdentifiers.pauseAction,
      title: "Pause"
    )
    let addFiveAction = UNNotificationAction(
      identifier: NotificationIdentifiers.addFiveMinutesAction,
      title: "+5 Minutes"
    )
    let timerFinishedCategory = UNNotificationCategory(
      identifier: NotificationIdentifiers.timerFinishedCategory,
      actions: [clearAction, repeatAction, addFiveAction],
      intentIdentifiers: [],
      options: []
    )
    let pomodoroAdvancingCategory = UNNotificationCategory(
      identifier: NotificationIdentifiers.pomodoroAdvancingCategory,
      actions: [skipBreakAction, pauseAction, stopPomodoroAction, addFiveAction],
      intentIdentifiers: [],
      options: []
    )
    let pomodoroCompleteCategory = UNNotificationCategory(
      identifier: NotificationIdentifiers.pomodoroCompleteCategory,
      actions: [clearAction, repeatAction],
      intentIdentifiers: [],
      options: []
    )
    let overrunCategory = UNNotificationCategory(
      identifier: NotificationIdentifiers.overrunExpiredCategory,
      actions: [clearAction],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([
      timerFinishedCategory,
      pomodoroAdvancingCategory,
      pomodoroCompleteCategory,
      overrunCategory,
    ])
  }

  private func observeSleepWake() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.model.checkSleepOverrun()
      }
    }
  }

  private func observeHotkeyDefaults() {
    guard hotkeyDefaultsObserver == nil else { return }
    hotkeyDefaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: UserDefaults.standard,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.reloadHotkeysFromDefaults()
        self?.updateStatusItem()
      }
    }
  }

  private func observeHotkeyChanges() {
    guard hotkeyChangeObserver == nil else { return }
    hotkeyChangeObserver = NotificationCenter.default.addObserver(
      forName: Hotkey.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.reloadHotkeysFromDefaults()
      }
    }
  }

  private func reloadHotkeysFromDefaults() {
    updateHotkey(.open, newHotkey: Hotkey.load(for: .open))
    updateHotkey(.pauseResume, newHotkey: Hotkey.load(for: .pauseResume))
    updateHotkey(.clear, newHotkey: Hotkey.load(for: .clear))
    updateHotkey(.startPomodoro, newHotkey: Hotkey.load(for: .startPomodoro))
    updateHotkey(.startStopwatch, newHotkey: Hotkey.load(for: .startStopwatch))
  }

  private func menuBarIconSize() -> NSSize {
    let rawValue = UserDefaults.standard.string(forKey: OnTimeSettingsKeys.menuBarIconSize)
    let size = MenuBarIconSize(rawValue: rawValue ?? "") ?? .default
    let pointSize: CGFloat
    switch size {
    case .small:
      pointSize = 16
    case .medium:
      pointSize = 18
    case .large:
      pointSize = 20
    }
    return NSSize(width: pointSize, height: pointSize)
  }

  private func updateHotkey(_ action: HotkeyAction, newHotkey: Hotkey?) {
    let currentHotkey = hotkey(for: action)
    guard currentHotkey != newHotkey else { return }
    unregisterHotkey(action)
    guard let newHotkey else {
      setHotkey(nil, for: action)
      return
    }
    if registerHotkey(newHotkey, for: action) {
      setHotkey(newHotkey, for: action)
    } else if let currentHotkey, registerHotkey(currentHotkey, for: action) {
      setHotkey(currentHotkey, for: action)
    }
  }

  private func hotkey(for action: HotkeyAction) -> Hotkey? {
    switch action {
    case .open:
      return currentOpenHotkey
    case .pauseResume:
      return currentPauseResumeHotkey
    case .clear:
      return currentClearHotkey
    case .startPomodoro:
      return currentStartPomodoroHotkey
    case .startStopwatch:
      return currentStartStopwatchHotkey
    }
  }

  private func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
    switch action {
    case .open:
      currentOpenHotkey = hotkey
    case .pauseResume:
      currentPauseResumeHotkey = hotkey
    case .clear:
      currentClearHotkey = hotkey
    case .startPomodoro:
      currentStartPomodoroHotkey = hotkey
    case .startStopwatch:
      currentStartStopwatchHotkey = hotkey
    }
  }

  private func registerHotkey(_ hotkey: Hotkey, for action: HotkeyAction) -> Bool {
    let signature = OSType(bitPattern: 0x4F4E544D)
    let hotKeyID = EventHotKeyID(signature: signature, id: action.id)
    var registeredHotKey: EventHotKeyRef?
    let modifiers = Hotkey.carbonFlags(from: hotkey.modifierFlags)
    let status = RegisterEventHotKey(
      UInt32(hotkey.keyCode),
      modifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &registeredHotKey
    )
    guard status == noErr else {
      print("Hotkey registration failed for \(action) status=\(status) keyCode=\(hotkey.keyCode) modifiers=\(modifiers)")
      NotificationCenter.default.post(
        name: Hotkey.registrationFailedNotification,
        object: nil,
        userInfo: [
          Hotkey.registrationFailedActionKey: action,
          Hotkey.registrationFailedStatusKey: Int(status)
        ]
      )
      return false
    }

    switch action {
    case .open:
      hotKeyRef = registeredHotKey
    case .pauseResume:
      pauseResumeHotKeyRef = registeredHotKey
    case .clear:
      trashHotKeyRef = registeredHotKey
    case .startPomodoro:
      startPomodoroHotKeyRef = registeredHotKey
    case .startStopwatch:
      startStopwatchHotKeyRef = registeredHotKey
    }

    installHotkeyHandlerIfNeeded()
    return true
  }

  private func unregisterHotkey(_ action: HotkeyAction) {
    let hotkeyRef: EventHotKeyRef?
    switch action {
    case .open:
      hotkeyRef = hotKeyRef
      self.hotKeyRef = nil
    case .pauseResume:
      hotkeyRef = pauseResumeHotKeyRef
      pauseResumeHotKeyRef = nil
    case .clear:
      hotkeyRef = trashHotKeyRef
      trashHotKeyRef = nil
    case .startPomodoro:
      hotkeyRef = startPomodoroHotKeyRef
      startPomodoroHotKeyRef = nil
    case .startStopwatch:
      hotkeyRef = startStopwatchHotKeyRef
      startStopwatchHotKeyRef = nil
    }
    if let hotkeyRef {
      UnregisterEventHotKey(hotkeyRef)
    }
  }

  private func installHotkeyHandlerIfNeeded() {
    guard hotKeyHandlerRef == nil else { return }
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
      guard let event, let userData else { return noErr }
      var hkID = EventHotKeyID()
      let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
      )
      guard status == noErr else { return status }
      let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
      DispatchQueue.main.async {
        guard let action = HotkeyAction(id: hkID.id) else { return }
        switch action {
        case .open:
          appDelegate.togglePopoverFromHotKey()
        case .pauseResume:
          appDelegate.togglePauseResumeFromHotKey()
        case .clear:
          appDelegate.trashFromHotKey()
        case .startPomodoro:
          appDelegate.model.startPomodoro()
        case .startStopwatch:
          appDelegate.model.startStopwatch()
        }
      }
      return noErr
    }, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &hotKeyHandlerRef)
  }

  private func startEventMonitors() {
    stopEventMonitors()
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      self?.handleGlobalMouseDown(event)
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      guard let self else { return event }
      if self.popover.isShown && event.keyCode == 53 {
        self.popover.performClose(nil)
        return nil
      }
      return event
    }
  }

  private func stopEventMonitors() {
    if let eventMonitor {
      NSEvent.removeMonitor(eventMonitor)
      self.eventMonitor = nil
    }
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  private func handleGlobalMouseDown(_ event: NSEvent) {
    guard popover.isShown else { return }
    let inPopover = isEventInPopover(event)
    let inStatusItem = isEventInStatusItem(event)
    if inPopover || inStatusItem {
      return
    }
    popover.performClose(nil)
  }

  private func isEventInPopover(_ event: NSEvent) -> Bool {
    guard let popoverWindow = popover.contentViewController?.view.window else { return false }
    return popoverWindow.frame.contains(event.locationInWindow)
  }

  private func isEventInStatusItem(_ event: NSEvent) -> Bool {
    guard let button = statusItem.button, let window = button.window else { return false }
    let buttonFrame = window.convertToScreen(button.frame)
    return buttonFrame.contains(event.locationInWindow)
  }

  private func applyHotkeyHint(for action: HotkeyAction, to item: NSMenuItem?) {
    guard let item else { return }
    guard let hotkey = Hotkey.load(for: action),
          let keyEquivalent = hotkey.menuKeyEquivalent else {
      item.keyEquivalent = ""
      item.keyEquivalentModifierMask = []
      return
    }
    item.keyEquivalent = keyEquivalent
    item.keyEquivalentModifierMask = hotkey.modifierFlags
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    return [.banner, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    switch response.actionIdentifier {
    case NotificationIdentifiers.clearAction:
      Task { @MainActor in
        self.model.stop()
      }
    case NotificationIdentifiers.stopPomodoroAction:
      Task { @MainActor in
        self.model.stop()
      }
    case NotificationIdentifiers.repeatAction:
      Task { @MainActor in
        _ = self.model.repeatLastInput()
      }
    case NotificationIdentifiers.skipBreakAction:
      Task { @MainActor in
        _ = self.model.skipPomodoroPhase()
      }
    case NotificationIdentifiers.pauseAction:
      Task { @MainActor in
        self.model.pause()
      }
    case NotificationIdentifiers.addFiveMinutesAction:
      Task { @MainActor in
        self.model.addTime(5 * 60)
      }
    case UNNotificationDefaultActionIdentifier:
      Task { @MainActor in
        self.showPopoverFromNotification()
      }
    default:
      break
    }
  }
}
