import AppKit
import SwiftUI

/// Pure pixel→duration mapping for stretch-to-set (unit-testable, no AppKit dependency in logic).
enum StretchTimerMapper {
  /// Vertical drag below this (pt) is a click / cancel — no timer.
  static let activationThreshold: CGFloat = 6
  static let minMinutes = 1
  static let maxMinutes = 180
  static let minSeconds = 1
  static let maxSeconds = 300

  /// - Parameters:
  ///   - deltaY: Downward drag distance in points (`max(0, anchorY - cursorY)`).
  ///   - isOptionHeld: `true` → seconds scale; `false` → minutes scale.
  /// - Returns: Duration in seconds, or `nil` when under the activation threshold.
  static func duration(deltaY: CGFloat, isOptionHeld: Bool) -> TimeInterval? {
    guard deltaY >= activationThreshold else { return nil }
    let effectiveY = deltaY - activationThreshold
    if isOptionHeld {
      return TimeInterval(seconds(fromEffectiveY: effectiveY))
    }
    return TimeInterval(minutes(fromEffectiveY: effectiveY) * 60)
  }

  /// Minutes piecewise curve (whole minutes).
  static func minutes(fromEffectiveY y: CGFloat) -> Int {
    let y = max(0, y)
    if y <= 180 {
      // 1...30 min @ ~6 pt / minute
      return min(30, max(minMinutes, Int(y / 6) + 1))
    }
    if y <= 300 {
      // 30...60 min in 5 min steps over 120 pt (~20 pt / step)
      let steps = Int((y - 180) / 20)
      return min(60, 30 + steps * 5)
    }
    // 60...180 min in 15 min steps (~25 pt / step)
    let steps = Int((y - 300) / 25)
    return min(maxMinutes, max(60, 60 + steps * 15))
  }

  /// Seconds piecewise curve (whole seconds).
  static func seconds(fromEffectiveY y: CGFloat) -> Int {
    let y = max(0, y)
    if y <= 300 {
      // 1...60 s @ ~5 pt / second
      return min(60, max(minSeconds, Int(y / 5) + 1))
    }
    // 60...300 s in 5 s steps (~15 pt / step)
    let steps = Int((y - 300) / 15)
    return min(maxSeconds, 60 + steps * 5)
  }

  static func hudLabel(duration: TimeInterval, isOptionHeld: Bool) -> String {
    if isOptionHeld {
      let seconds = max(minSeconds, Int(duration.rounded()))
      return "\(seconds) s"
    }
    let totalMinutes = max(minMinutes, Int((duration / 60).rounded()))
    if totalMinutes < 60 {
      return "\(totalMinutes) min"
    }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if minutes == 0 {
      return "\(hours)h"
    }
    return "\(hours)h \(minutes)m"
  }
}

// MARK: - Overlay

/// Full-screen stretch HUD that can become key so Esc cancels without relying on the
/// frontmost app forwarding key events into our tracking loop.
private final class StretchCancelPanel: NSPanel {
  var onEscape: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {  // Esc
      onEscape?()
      return
    }
    super.keyDown(with: event)
  }
}

enum StretchDismissAnimation {
  static let successSpringResponse: Double = 0.48
  static let successSpringDamping: Double = 0.72
}

@MainActor
final class MenuBarStretchOverlay {
  private var panel: StretchCancelPanel?
  private var model = StretchOverlayModel()
  private var hostingView: NSHostingView<StretchOverlayRoot>?
  private var lastHapticLabel: String?
  private var dismissGeneration = 0

  /// Invoked when the user presses Esc while the stretch HUD is key.
  var onEscape: (() -> Void)? {
    didSet { panel?.onEscape = onEscape }
  }

  var isVisible: Bool { panel?.isVisible == true }

  var dismissPhase: StretchDismissPhase { model.dismissPhase }

  func show(anchorInScreen: NSPoint, on screen: NSScreen) {
    dismissGeneration += 1
    let frame = screen.frame
    if panel == nil {
      let panel = StretchCancelPanel(
        contentRect: frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      panel.level = .statusBar
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      // Mouse must pass through so status-item tracking keeps seeing the drag.
      panel.ignoresMouseEvents = true
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.hidesOnDeactivate = false
      panel.onEscape = onEscape
      let root = StretchOverlayRoot(model: model)
      let hosting = NSHostingView(rootView: root)
      hosting.frame = NSRect(origin: .zero, size: frame.size)
      panel.contentView = hosting
      self.panel = panel
      self.hostingView = hosting
    }

    panel?.setFrame(frame, display: true)
    hostingView?.frame = NSRect(origin: .zero, size: frame.size)

    model.resetForShow(screenFrame: frame, anchor: anchorInScreen)
    lastHapticLabel = nil

    // Become key so Esc reaches us while the mouse is still held on the status item.
    panel?.makeKeyAndOrderFront(nil)
  }

  /// Updates visuals from current cursor; returns mapped duration, or `nil` in the cancel zone
  /// or while settle/fade animations hold live updates.
  @discardableResult
  func update(cursorInScreen: NSPoint, isOptionHeld: Bool) -> TimeInterval? {
    guard !model.ignoresLiveUpdates else { return nil }

    let deltaY = max(0, model.anchorInScreen.y - cursorInScreen.y)
    let duration = StretchTimerMapper.duration(deltaY: deltaY, isOptionHeld: isOptionHeld)
    let clampedY = min(model.anchorInScreen.y, cursorInScreen.y)
    let label: String
    if let duration {
      label = StretchTimerMapper.hudLabel(duration: duration, isOptionHeld: isOptionHeld)
      if label != lastHapticLabel {
        lastHapticLabel = label
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
      }
    } else {
      label = ""
      lastHapticLabel = nil
    }

    // Live drag must track the cursor with no fade/tween — keep animations for settle only.
    var live = Transaction()
    live.disablesAnimations = true
    withTransaction(live) {
      model.cursorInScreen = cursorInScreen
      model.isOptionHeld = isOptionHeld
      model.applyLiveKnobY(clampedY)
      model.isActive = duration != nil
      model.hudLabel = label
    }
    return duration
  }

  func settleSuccess(completion: (() -> Void)? = nil) {
    guard panel?.isVisible == true else {
      completion?()
      return
    }
    releaseKeyFocusForDismiss()
    dismissGeneration += 1
    let generation = dismissGeneration
    model.beginSuccessSettle()

    // Elastic snap only — no fade overlay on release.
    withAnimation(
      .spring(
        response: StretchDismissAnimation.successSpringResponse,
        dampingFraction: StretchDismissAnimation.successSpringDamping
      )
    ) {
      model.knobYInScreen = model.anchorInScreen.y
    }

    DispatchQueue.main.asyncAfter(
      deadline: .now() + StretchDismissAnimation.successSpringResponse + 0.05
    ) { [weak self] in
      guard let self, self.dismissGeneration == generation else { return }
      self.finishAnimatedDismiss(completion: completion)
    }
  }

  /// Cancel instantly (no fade) — used for Esc / failed stretch.
  func fadeCancel(completion: (() -> Void)? = nil) {
    guard panel?.isVisible == true else {
      completion?()
      return
    }
    releaseKeyFocusForDismiss()
    dismissGeneration += 1
    finishAnimatedDismiss(completion: completion)
  }

  /// Drop key focus so the HUD can animate without holding keyboard activation.
  /// The panel sets `hidesOnDeactivate = false`, so deactivating does not order it out.
  private func releaseKeyFocusForDismiss() {
    panel?.resignKey()
    NSApp.deactivate()
  }

  private func finishAnimatedDismiss(completion: (() -> Void)?) {
    model.finishDismiss()
    panel?.orderOut(nil)
    model.isActive = false
    model.hudLabel = ""
    lastHapticLabel = nil
    completion?()
  }

  func dismiss() {
    dismissGeneration += 1
    model.finishDismiss()
    panel?.orderOut(nil)
    model.isActive = false
    model.hudLabel = ""
    lastHapticLabel = nil
  }
}

enum StretchDismissPhase: Equatable {
  case idle
  case settling
  case fading
  case hidden
}

@MainActor
final class StretchOverlayModel: ObservableObject {
  @Published var screenFrame: NSRect = .zero
  @Published var anchorInScreen: NSPoint = .zero
  @Published var cursorInScreen: NSPoint = .zero
  @Published var knobYInScreen: CGFloat = 0
  @Published var isOptionHeld = false
  @Published var hudLabel = ""
  @Published var isActive = false
  @Published var dismissPhase: StretchDismissPhase = .idle

  var ignoresLiveUpdates: Bool {
    dismissPhase == .settling || dismissPhase == .fading
  }

  func resetForShow(screenFrame: NSRect, anchor: NSPoint) {
    self.screenFrame = screenFrame
    anchorInScreen = anchor
    cursorInScreen = anchor
    knobYInScreen = anchor.y
    isOptionHeld = false
    hudLabel = ""
    isActive = false
    dismissPhase = .idle
  }

  func applyLiveKnobY(_ y: CGFloat) {
    guard !ignoresLiveUpdates else { return }
    knobYInScreen = y
  }

  func beginSuccessSettle() {
    dismissPhase = .settling
  }

  func finishDismiss() {
    dismissPhase = .hidden
  }
}

private struct StretchOverlayRoot: View {
  @ObservedObject var model: StretchOverlayModel

  var body: some View {
    GeometryReader { geo in
      let localAnchor = toLocal(model.anchorInScreen, in: geo.size)
      let localKnob = toLocal(
        NSPoint(x: model.anchorInScreen.x, y: model.knobYInScreen),
        in: geo.size
      )
      let accent = model.isOptionHeld ? Color(nsColor: .systemPink) : Color(nsColor: .systemBlue)
      let knobY = localKnob.y
      let lineTop = min(localAnchor.y, knobY)
      let lineBottom = max(localAnchor.y, knobY)
      let showHud = model.isActive || model.dismissPhase == .settling

      ZStack(alignment: .topLeading) {
        Color.clear

        // Elastic line — height/position update instantly while dragging.
        // No opacity/transition: default SwiftUI insert fade is what looked like drag fade.
        if model.isActive || model.dismissPhase == .settling {
          Capsule()
            .fill(Color.white.opacity(0.65))
            .frame(width: 6, height: max(0, lineBottom - lineTop + 2))
            .position(x: localAnchor.x, y: (lineTop + lineBottom) / 2)
            .transition(.identity)

          Capsule()
            .fill(accent)
            .frame(width: 4, height: max(0, lineBottom - lineTop))
            .position(x: localAnchor.x, y: (lineTop + lineBottom) / 2)
            .transition(.identity)

          // Dragging knob only — no fixed starting circle at the menu-bar anchor.
          ZStack {
            Circle()
              .stroke(Color.white.opacity(0.55), lineWidth: 2)
              .frame(width: 18, height: 18)
            Circle()
              .fill(accent)
              .frame(width: 14, height: 14)
          }
          .position(x: localAnchor.x, y: knobY)
          .transition(.identity)
        }

        if showHud, !model.hudLabel.isEmpty {
          hudPill(accent: accent)
            .position(hudPosition(anchorX: localAnchor.x, knobY: knobY, width: geo.size.width))
            .transition(.identity)
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .animation(nil, value: model.isActive)
      .animation(nil, value: model.hudLabel)
      .animation(nil, value: model.isOptionHeld)
      // Knob Y: animate only during elastic settle; live drag is instant.
      .animation(
        model.dismissPhase == .settling
          ? .spring(
            response: StretchDismissAnimation.successSpringResponse,
            dampingFraction: StretchDismissAnimation.successSpringDamping
          )
          : nil,
        value: model.knobYInScreen
      )
      .transaction { transaction in
        if model.dismissPhase == .idle {
          transaction.disablesAnimations = true
          transaction.animation = nil
        }
      }
    }
  }

  private func hudPill(accent: Color) -> some View {
    Text(model.hudLabel)
      .font(.system(size: 16, weight: .bold).monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.black.opacity(0.68))
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(Color.white.opacity(0.18), lineWidth: 1)
          )
          .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
      )
  }

  private func hudPosition(anchorX: CGFloat, knobY: CGFloat, width: CGFloat) -> CGPoint {
    let pillHalfWidth: CGFloat = 48
    let offset: CGFloat = 16 + pillHalfWidth
    let preferLeft = anchorX - offset > 24
    let x = preferLeft ? anchorX - offset : anchorX + offset
    return CGPoint(x: min(max(x, pillHalfWidth + 8), width - pillHalfWidth - 8), y: knobY)
  }

  /// Convert Cocoa screen coordinates into top-left SwiftUI local space for this panel.
  private func toLocal(_ screenPoint: NSPoint, in size: CGSize) -> CGPoint {
    let x = screenPoint.x - model.screenFrame.minX
    let yFromBottom = screenPoint.y - model.screenFrame.minY
    let y = size.height - yFromBottom
    return CGPoint(x: x, y: y)
  }
}

// MARK: - Status item hit target

/// Transparent overlay on `NSStatusBarButton` so we own `mouseDown` (status-item actions
/// often never see drag events). Tracking uses the standard AppKit `nextEvent` loop.
final class StatusItemHitView: NSView {
  var onLeftMouseDown: ((NSEvent) -> Void)?
  var onRightMouseUp: ((NSEvent) -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // Always claim hits inside our bounds so the button doesn't steal them.
    bounds.contains(point) ? self : nil
  }

  override func mouseDown(with event: NSEvent) {
    onLeftMouseDown?(event)
  }

  override func rightMouseUp(with event: NSEvent) {
    onRightMouseUp?(event)
  }

  override func rightMouseDown(with event: NSEvent) {
    // Consume so the button doesn't also show a menu.
  }
}
