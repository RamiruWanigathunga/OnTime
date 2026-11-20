import XCTest
@testable import OnTime

@MainActor
final class AppIntentsTests: XCTestCase {
  private var model: OnTimeModel!

  override func setUp() {
    super.setUp()
    model = OnTimeModel()
  }

  override func tearDown() {
    model.stop()
    model = nil
    super.tearDown()
  }

  func testDurationSecondsFromMinutesAndSeconds() {
    XCTAssertEqual(
      OnTimeIntentSupport.durationSeconds(minutes: 25, seconds: 0) ?? -1, 1500, accuracy: 0.01)
    XCTAssertEqual(
      OnTimeIntentSupport.durationSeconds(minutes: 0, seconds: 45) ?? -1, 45, accuracy: 0.01)
    XCTAssertEqual(
      OnTimeIntentSupport.durationSeconds(minutes: 1, seconds: 30) ?? -1, 90, accuracy: 0.01)
    XCTAssertNil(OnTimeIntentSupport.durationSeconds(minutes: 0, seconds: 0))
    XCTAssertNil(OnTimeIntentSupport.durationSeconds(minutes: nil, seconds: nil))
  }

  func testAdjustmentSecondsAddAndSubtract() {
    XCTAssertEqual(
      OnTimeIntentSupport.adjustmentSeconds(minutes: 5, seconds: 0, subtract: false) ?? 0, 300,
      accuracy: 0.01)
    XCTAssertEqual(
      OnTimeIntentSupport.adjustmentSeconds(minutes: 0, seconds: 30, subtract: true) ?? 0, -30,
      accuracy: 0.01)
    XCTAssertNil(OnTimeIntentSupport.adjustmentSeconds(minutes: 0, seconds: 0, subtract: false))
  }

  func testStartCountdownParametersDriveModel() {
    let duration = OnTimeIntentSupport.durationSeconds(minutes: 2, seconds: 0)!
    model.start(duration: duration, isTimeOfDay: false)
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.mode, .countdown)
    XCTAssertEqual(model.remaining, 120, accuracy: 1.5)
  }

  func testAdjustParametersDriveModel() {
    model.start(duration: 120, isTimeOfDay: false)
    let delta = OnTimeIntentSupport.adjustmentSeconds(minutes: 1, seconds: 0, subtract: false)!
    XCTAssertTrue(model.applyRelativeAdjustment(delta))
    XCTAssertEqual(model.remaining, 180, accuracy: 1.5)

    let subtract = OnTimeIntentSupport.adjustmentSeconds(minutes: 0, seconds: 30, subtract: true)!
    XCTAssertTrue(model.applyRelativeAdjustment(subtract))
    XCTAssertEqual(model.remaining, 150, accuracy: 1.5)
  }

  func testStatusDialogIdleAndCountdown() {
    XCTAssertEqual(OnTimeIntentSupport.statusDialog(for: model), "No timer is running.")
    XCTAssertEqual(OnTimeIntentSupport.statusValue(for: model), "Idle")

    model.start(duration: 90, isTimeOfDay: false)
    let dialog = OnTimeIntentSupport.statusDialog(for: model)
    XCTAssertTrue(dialog.contains("remaining"), dialog)
    let value = OnTimeIntentSupport.statusValue(for: model)
    XCTAssertTrue(value.hasPrefix("Countdown"), value)
    XCTAssertTrue(value.contains("remaining"), value)
  }

  func testStatusDialogStopwatchAndPause() {
    model.startStopwatch()
    XCTAssertTrue(OnTimeIntentSupport.statusDialog(for: model).contains("Stopwatch"))
    model.pause()
    XCTAssertTrue(OnTimeIntentSupport.statusDialog(for: model).contains("paused"))
    XCTAssertTrue(OnTimeIntentSupport.statusValue(for: model).contains("paused"))
  }

  func testNaturalLanguagePathMatchesIntent() {
    model.inputDuration = "25m"
    let preview = model.previewForInput("25m")
    XCTAssertNotNil(preview)
    XCTAssertTrue(model.startFromInputs())
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.remaining, 1500, accuracy: 1.5)
  }
}
