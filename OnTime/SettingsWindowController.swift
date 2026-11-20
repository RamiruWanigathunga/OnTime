import AppKit
import QuartzCore
import SwiftUI

/// Borderless panels report `canBecomeKey == false`. Settings must be key so
/// Escape and `windowDidResignKey` can dismiss it.
private final class KeyableSettingsPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()
  static let settingsWillCloseNotification = Notification.Name("OnTimeSettingsWillClose")
  static let settingsDidResignKeyNotification = Notification.Name("OnTimeSettingsDidResignKey")

  /// When true, resign-key must not auto-dismiss (open panel / alert).
  var isPresentingModal = false

  /// True while a KeyboardShortcuts recorder field is first responder.
  private var isShortcutRecorderFocused: Bool {
    var responder = panel?.firstResponder
    while let current = responder {
      if current is NSSearchField || current is NSTextField || current is NSTextView {
        return true
      }
      responder = current.nextResponder
    }
    return false
  }

  /// KeyboardShortcuts conflict alerts use sheets / `runModal`; recording uses
  /// an NSSearchField — none of those should dismiss Settings.
  private var shouldSuppressAutoDismiss: Bool {
    isPresentingModal
      || panel?.attachedSheet != nil
      || NSApp.modalWindow != nil
      || isShortcutRecorderFocused
  }

  private var panel: NSPanel?
  private let presentation = SettingsPresentationModel()
  private var escapeMonitor: Any?
  private var dismissGeneration = 0
  /// Menu-bar (.accessory) activation churn from closing the popover resigns
  /// key immediately; ignore that resign until the open settle finishes.
  private var suppressResignUntil: Date = .distantPast

  func show() {
    dismissGeneration += 1
    let panel = ensurePanel()
    centerPanel(panel)
    presentation.resetForShow()
    presentation.beginAppear()
    // Keep the window fully opaque so Sequoia vibrancy samples the desktop;
    // blur/fade/scale live on the SwiftUI content.
    panel.alphaValue = 1
    suppressResignUntil = Date().addingTimeInterval(
      SettingsPresentationMotion.openDuration
        + SettingsPresentationMotion.staggerMax + 0.35
    )
    NSApp.unhide(nil)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    installEscapeMonitor()

    withAnimation(
      .easeOut(duration: SettingsPresentationMotion.openDuration)
    ) {
      presentation.applySettledAppearance()
    }
    DispatchQueue.main.asyncAfter(
      deadline: .now() + SettingsPresentationMotion.openDuration
        + SettingsPresentationMotion.staggerMax
    ) { [weak self] in
      self?.presentation.markVisible()
    }
  }

  func closeAnimated() {
    guard presentation.beginDismiss() else { return }
    dismissGeneration += 1
    let generation = dismissGeneration
    // Ignore further resign-key while the parallax blur-slide plays.
    suppressResignUntil = Date.distantFuture
    removeEscapeMonitor()
    NotificationCenter.default.post(name: Self.settingsWillCloseNotification, object: nil)

    guard let panel else {
      presentation.finishHidden()
      return
    }

    // Drive per-piece SwiftUI motion; keep a light window fade as a safety net
    // so resign-key dismiss still reads if a transaction is dropped.
    let duration =
      SettingsPresentationMotion.closeDuration + SettingsPresentationMotion.staggerMax
    DispatchQueue.main.async {
      withAnimation(.easeIn(duration: SettingsPresentationMotion.closeDuration)) {
        self.presentation.applyDismissAppearance()
      }
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak self] in
      guard let self, self.dismissGeneration == generation else { return }
      panel.orderOut(nil)
      panel.alphaValue = 1
      self.suppressResignUntil = .distantPast
      self.presentation.finishHidden()
    }
  }

  private func ensurePanel() -> NSPanel {
    if let panel { return panel }

    let root = OnTimeSettingsView(
      presentation: presentation,
      onClose: { [weak self] in self?.closeAnimated() },
      onSelectAbout: { [weak self] in
        _ = self
      }
    )
    let hosting = NSHostingController(rootView: root)
    hosting.view.wantsLayer = true
    hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
    // NSHostingView often paints an opaque/translucent plate behind SwiftUI;
    // clear the whole chain so only the three glass panels are visible.
    Self.clearViewBackgrounds(from: hosting.view)

    let panel = KeyableSettingsPanel(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.moveToActiveSpace]
    panel.contentViewController = hosting
    panel.contentView?.wantsLayer = true
    panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    Self.clearViewBackgrounds(from: panel.contentView)
    panel.setContentSize(NSSize(width: 760, height: 560))
    panel.minSize = NSSize(width: 700, height: 480)
    panel.delegate = self
    self.panel = panel

    // Hosting installs extra wrapper views after the first layout pass.
    DispatchQueue.main.async { [weak panel, weak hosting] in
      Self.clearViewBackgrounds(from: hosting?.view)
      Self.clearViewBackgrounds(from: panel?.contentView)
    }
    return panel
  }

  /// Walk AppKit subviews and clear non-vibrancy fills so the Settings window
  /// does not show a full-size frosted “shade plate” behind the glass panels.
  private static func clearViewBackgrounds(from root: NSView?) {
    guard let root else { return }
    var stack: [NSView] = [root]
    while let view = stack.popLast() {
      // Keep intentional glass materials on SettingsGlassPanel backdrops.
      if !(view is NSVisualEffectView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
      }
      stack.append(contentsOf: view.subviews)
    }
  }

  private func centerPanel(_ panel: NSPanel) {
    let screenFrame = NSScreen.main?.visibleFrame ?? panel.screen?.visibleFrame
    guard let screenFrame else { return }
    let size = panel.frame.size
    panel.setFrameOrigin(
      NSPoint(
        x: screenFrame.midX - size.width / 2,
        y: screenFrame.midY - size.height / 2
      )
    )
  }

  private func installEscapeMonitor() {
    removeEscapeMonitor()
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      if event.keyCode == 53 {  // Escape
        let consume = MainActor.assumeIsolated { () -> Bool in
          guard event.window === self.panel else { return false }
          // Let the shortcut recorder own Escape while recording / focused.
          guard !self.shouldSuppressAutoDismiss else { return false }
          self.closeAnimated()
          return true
        }
        return consume ? nil : event
      }
      return event
    }
  }

  private func removeEscapeMonitor() {
    if let escapeMonitor {
      NSEvent.removeMonitor(escapeMonitor)
      self.escapeMonitor = nil
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    NotificationCenter.default.post(name: Self.settingsDidResignKeyNotification, object: nil)
    // Never reclaim or re-enter dismiss while the blur-fade is already playing.
    guard presentation.phase != .dismissing && presentation.phase != .hidden else { return }

    if Date() < suppressResignUntil || presentation.phase == .appearing {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard self.presentation.phase == .appearing || self.presentation.phase == .visible else {
          return
        }
        NSApp.activate(ignoringOtherApps: true)
        self.panel?.makeKeyAndOrderFront(nil)
      }
      return
    }

    // Defer one turn so KeyboardShortcuts’ system-conflict alert can become
    // the modal window before we decide to auto-dismiss.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard !self.shouldSuppressAutoDismiss else { return }
      guard self.presentation.phase == .visible else { return }
      guard self.panel?.isKeyWindow != true else { return }
      self.closeAnimated()
    }
  }

  func windowWillClose(_ notification: Notification) {
    removeEscapeMonitor()
    NotificationCenter.default.post(name: Self.settingsWillCloseNotification, object: nil)
  }
}
