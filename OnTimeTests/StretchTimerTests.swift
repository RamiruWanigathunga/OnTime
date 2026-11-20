import AppKit
import XCTest
@testable import OnTime

final class StretchTimerTests: XCTestCase {
  func testSubThresholdReturnsNil() {
    XCTAssertNil(StretchTimerMapper.duration(deltaY: 0, isOptionHeld: false))
    XCTAssertNil(StretchTimerMapper.duration(deltaY: 5.9, isOptionHeld: false))
    XCTAssertNil(StretchTimerMapper.duration(deltaY: 5, isOptionHeld: true))
  }

  func testMinutesModeMappingAndClamps() {
    XCTAssertEqual(
      StretchTimerMapper.duration(deltaY: 6, isOptionHeld: false) ?? -1, 60, accuracy: 0.1)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 0), 1)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 6), 2)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 174), 30)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 180), 30)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 200), 35)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 300), 60)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 325), 75)
    XCTAssertEqual(StretchTimerMapper.minutes(fromEffectiveY: 10_000), 180)
    XCTAssertEqual(
      StretchTimerMapper.duration(deltaY: 6 + 10_000, isOptionHeld: false) ?? -1,
      180 * 60,
      accuracy: 0.1
    )
  }

  func testSecondsModeMappingAndClamps() {
    XCTAssertEqual(
      StretchTimerMapper.duration(deltaY: 6, isOptionHeld: true) ?? -1, 1, accuracy: 0.1)
    XCTAssertEqual(StretchTimerMapper.seconds(fromEffectiveY: 0), 1)
    XCTAssertEqual(StretchTimerMapper.seconds(fromEffectiveY: 5), 2)
    XCTAssertEqual(StretchTimerMapper.seconds(fromEffectiveY: 295), 60)
    XCTAssertEqual(StretchTimerMapper.seconds(fromEffectiveY: 300), 60)
    XCTAssertEqual(StretchTimerMapper.seconds(fromEffectiveY: 315), 65)
    XCTAssertEqual(StretchTimerMapper.seconds(fromEffectiveY: 10_000), 300)
  }

  func testHudLabelFormatting() {
    XCTAssertEqual(StretchTimerMapper.hudLabel(duration: 9, isOptionHeld: true), "9 s")
    XCTAssertEqual(StretchTimerMapper.hudLabel(duration: 10, isOptionHeld: true), "10 s")
    XCTAssertEqual(StretchTimerMapper.hudLabel(duration: 45, isOptionHeld: true), "45 s")
    XCTAssertEqual(StretchTimerMapper.hudLabel(duration: 13 * 60, isOptionHeld: false), "13 min")
    XCTAssertEqual(StretchTimerMapper.hudLabel(duration: 60 * 60, isOptionHeld: false), "1h")
    XCTAssertEqual(
      StretchTimerMapper.hudLabel(duration: 90 * 60, isOptionHeld: false), "1h 30m")
  }

  func testDefaultSettingIsOn() {
    XCTAssertTrue(StretchTimerDefaults.isEnabled)
    XCTAssertEqual(OnTimeSettingsKeys.stretchToSetTimer, "stretchToSetTimer")
  }

  @MainActor
  func testStartStretchedCountdownStartsAndStoresRepeatInput() {
    let model = OnTimeModel()
    defer { model.stop() }

    model.startStretchedCountdown(duration: 90)
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.mode, .countdown)
    XCTAssertEqual(model.remaining, 90, accuracy: 0.5)
    XCTAssertEqual(model.inputDuration, model.formatCompactDuration(90))
  }

  @MainActor
  func testDismissPhaseSuccessPath() {
    let model = StretchOverlayModel()
    model.resetForShow(
      screenFrame: NSRect(x: 0, y: 0, width: 100, height: 100),
      anchor: NSPoint(x: 50, y: 90)
    )
    XCTAssertEqual(model.dismissPhase, .idle)
    XCTAssertEqual(model.knobYInScreen, 90, accuracy: 0.001)

    model.applyLiveKnobY(40)
    XCTAssertEqual(model.knobYInScreen, 40, accuracy: 0.001)

    model.beginSuccessSettle()
    XCTAssertEqual(model.dismissPhase, .settling)
    XCTAssertTrue(model.ignoresLiveUpdates)
    model.applyLiveKnobY(10)
    XCTAssertEqual(model.knobYInScreen, 40, accuracy: 0.001)

    model.finishDismiss()
    XCTAssertEqual(model.dismissPhase, .hidden)
  }

  @MainActor
  func testSettleSuccessKeepsPanelVisibleCancelIsInstant() {
    guard let screen = NSScreen.main else {
      XCTFail("Need a screen to verify the stretch panel stays ordered in")
      return
    }
    let overlay = MenuBarStretchOverlay()
    let anchor = NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 20)
    overlay.show(anchorInScreen: anchor, on: screen)
    XCTAssertTrue(overlay.isVisible)
    XCTAssertEqual(overlay.dismissPhase, .idle)

    overlay.settleSuccess()
    XCTAssertTrue(overlay.isVisible, "settleSuccess must keep the panel visible while the elastic spring runs")
    XCTAssertEqual(overlay.dismissPhase, .settling)
    overlay.dismiss()
    XCTAssertFalse(overlay.isVisible)

    overlay.show(anchorInScreen: anchor, on: screen)
    XCTAssertTrue(overlay.isVisible)
    XCTAssertEqual(overlay.dismissPhase, .idle)

    overlay.fadeCancel()
    XCTAssertFalse(overlay.isVisible, "cancel dismisses instantly with no fade")
    XCTAssertEqual(overlay.dismissPhase, .hidden)
  }

  @MainActor
  func testFinishDismissClearsPhase() {
    let model = StretchOverlayModel()
    model.resetForShow(
      screenFrame: NSRect(x: 0, y: 0, width: 100, height: 100),
      anchor: NSPoint(x: 50, y: 90)
    )
    model.applyLiveKnobY(55)
    model.finishDismiss()
    XCTAssertEqual(model.dismissPhase, .hidden)
    XCTAssertFalse(model.ignoresLiveUpdates)
  }

  @MainActor
  func testStartStretchedCountdownEnablesRepeatAfterFinish() {
    let model = OnTimeModel()
    defer { model.stop() }

    model.startStretchedCountdown(duration: 30)
    XCTAssertTrue(model.applyRelativeAdjustment(-30))
    XCTAssertTrue(model.isFinished)
    XCTAssertTrue(model.canRepeat)
    XCTAssertTrue(model.repeatLastInput())
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.remaining, 30, accuracy: 1.0)
  }
}
