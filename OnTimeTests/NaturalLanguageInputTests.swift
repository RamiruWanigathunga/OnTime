import XCTest
@testable import OnTime

final class NaturalLanguageInputTests: XCTestCase {
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

  func testComplexConjunctionDurations() {
    XCTAssertEqual(model.parsedDuration(from: "1 hour and 39 min"), 99 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedDuration(from: "1h plus 15m"), 75 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedDuration(from: "2h & 30 min"), 150 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedDuration(from: "1 hour, 20 minutes"), 80 * 60, accuracy: 0.1)
  }

  func testRelativeParsing() {
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+5") ?? 0, 5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+5m") ?? 0, 5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+ 5m") ?? 0, 5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+5 min") ?? 0, 5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+ 33sec") ?? 0, 33, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+33s") ?? 0, 33, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "add 5 min") ?? 0, 5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "add 1h 15m") ?? 0, 75 * 60, accuracy: 0.1)

    XCTAssertEqual(model.parsedRelativeAdjustment(from: "-10s") ?? 0, -10, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "- 10s") ?? 0, -10, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "-2m") ?? 0, -2 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "-33m") ?? 0, -33 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "- 33 min") ?? 0, -33 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "subtract 5 min") ?? 0, -5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "minus 2m") ?? 0, -2 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "subtract 30s") ?? 0, -30, accuracy: 0.1)

    XCTAssertNil(model.parsedRelativeAdjustment(from: "25m"))
    XCTAssertNil(model.parsedRelativeAdjustment(from: ""))
  }

  func testPreviewForComplexAndRelative() {
    XCTAssertEqual(model.previewForInput("1 hour and 39 min"), "1h 39m")
    XCTAssertEqual(model.previewForInput("+5"), "Start 5m timer")
    XCTAssertEqual(model.previewForInput("+5m"), "Start 5m timer")
    XCTAssertEqual(model.previewForInput("add 5 min"), "Start 5m timer")
    XCTAssertEqual(model.previewForInput("-10s"), nil)
    XCTAssertEqual(model.previewForInput("-2m"), nil)
    XCTAssertEqual(model.previewForInput("pomo"), "Start Pomodoro")
    XCTAssertNil(model.previewForInput("skip"))

    model.start(duration: 10 * 60)
    XCTAssertEqual(model.previewForInput("+5m"), "Add 5m to current timer")
    XCTAssertEqual(model.previewForInput("-10s"), "Subtract 10s from current timer")
    XCTAssertEqual(model.previewForInput("add 1h 15m"), "Add 1h 15m to current timer")
    XCTAssertNil(model.previewForInput("skip"))
  }

  func testIdlePositiveRelativeStartsCountdown() {
    model.inputDuration = "+5m"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertTrue(model.isRunning)
    XCTAssertFalse(model.isFinished)
    XCTAssertEqual(model.remaining, 5 * 60, accuracy: 1)
  }

  func testIdleNegativeRelativeIsNoOp() {
    model.inputDuration = "-10s"
    XCTAssertFalse(model.startFromInputs())
    XCTAssertFalse(model.isRunning)
    XCTAssertEqual(model.inputDuration, "-10s")
  }

  func testRunningRelativeAdjustsRemaining() {
    model.start(duration: 10 * 60)
    let endsBefore = model.timeOfDayEndTooltip

    model.inputDuration = "+5m"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertEqual(model.remaining, 15 * 60, accuracy: 1)
    let endsAfterAdd = model.timeOfDayEndTooltip
    XCTAssertNotNil(endsBefore)
    XCTAssertNotNil(endsAfterAdd)
    // End time should move later after adding five minutes.
    XCTAssertNotEqual(endsBefore, endsAfterAdd)

    model.inputDuration = "-10s"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertEqual(model.remaining, 15 * 60 - 10, accuracy: 1)
  }

  func testPausedRelativeAdjustsRemaining() {
    model.start(duration: 8 * 60)
    model.pause()
    XCTAssertTrue(model.isPaused)
    XCTAssertNil(model.timeOfDayEndTooltip)

    model.inputDuration = "+2m"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertEqual(model.remaining, 10 * 60, accuracy: 1)
    XCTAssertTrue(model.isPaused)
    XCTAssertNil(model.timeOfDayEndTooltip)

    model.inputDuration = "-30s"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertEqual(model.remaining, 10 * 60 - 30, accuracy: 1)
    XCTAssertTrue(model.isPaused)
  }

  func testAddTimeClampsAtZero() {
    model.start(duration: 30)
    model.addTime(-120)
    XCTAssertTrue(model.isFinished || model.remaining == 0)
  }

  func testSubtractMoreThanRemainingFinishesCleanly() {
    model.start(duration: 45)
    model.inputDuration = "-2m"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertTrue(model.isFinished)
    XCTAssertEqual(model.remaining, 0, accuracy: 0.1)
  }

  func testFinishedPositiveRelativeStartsNewCountdown() {
    model.start(duration: 1)
    model.addTime(-10)
    XCTAssertTrue(model.isFinished)

    model.inputDuration = "+5m"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertTrue(model.isRunning)
    XCTAssertFalse(model.isFinished)
    XCTAssertEqual(model.remaining, 5 * 60, accuracy: 1)
  }

  func testStopwatchIgnoresRelativeAdjustment() {
    model.startStopwatch()
    model.inputDuration = "+5m"
    XCTAssertNil(model.previewForInput("+5m"))
    XCTAssertFalse(model.startFromInputs())
    XCTAssertEqual(model.mode, .stopwatch)
    XCTAssertTrue(model.isRunning)
  }

  func testSkipInputDuringPomodoroAdvancesPhase() {
    model.startPomodoro()
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .work)
    XCTAssertEqual(model.previewForInput("skip"), "Skip Work")
    XCTAssertEqual(model.previewForInput("skip phase"), "Skip Work")
    XCTAssertEqual(model.previewForInput("skip work"), "Skip Work")

    model.inputDuration = "skip"
    XCTAssertTrue(model.startFromInputs())
    XCTAssertEqual(model.pomodoroSession?.currentPhase, .shortBreak)
    XCTAssertEqual(model.inputDuration, "")
    XCTAssertEqual(model.previewForInput("skip break"), "Skip Break")
    XCTAssertEqual(model.previewForInput("skip"), "Skip Break")
  }

  func testSkipInputIdleAndCountdownAreNoOp() {
    model.inputDuration = "skip"
    XCTAssertNil(model.previewForInput("skip"))
    XCTAssertFalse(model.startFromInputs())
    XCTAssertFalse(model.isRunning)
    XCTAssertEqual(model.inputDuration, "skip")

    model.start(duration: 5 * 60)
    model.inputDuration = "skip phase"
    XCTAssertNil(model.previewForInput("skip phase"))
    XCTAssertFalse(model.startFromInputs())
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.pomodoroSession?.isActive, nil)
    XCTAssertEqual(model.inputDuration, "skip phase")
  }
}
