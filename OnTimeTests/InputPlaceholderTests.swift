import XCTest
@testable import OnTime

final class InputPlaceholderTests: XCTestCase {
  func testDefaultPoolIncludesStopwatchAndPomodoro() {
    XCTAssertTrue(OnTimeInputPlaceholders.defaults.contains("stopwatch"))
    XCTAssertTrue(OnTimeInputPlaceholders.defaults.contains("pomodoro"))
    XCTAssertEqual(OnTimeInputPlaceholders.defaults.last, "stopwatch")
  }

  func testIdlePoolExcludesRelativeAndSkip() {
    let pool = OnTimeInputPlaceholders.pool(
      isRunning: false,
      isFinished: false,
      mode: .countdown,
      isPomodoroActive: false
    )
    XCTAssertEqual(pool, OnTimeInputPlaceholders.defaults)
    XCTAssertFalse(pool.contains("+5 min"))
    XCTAssertFalse(pool.contains("-2 min"))
    XCTAssertFalse(pool.contains("+45 sec"))
    XCTAssertFalse(pool.contains("Add 30min"))
    XCTAssertFalse(pool.contains("skip"))
  }

  func testRunningCountdownPoolIncludesRelativeExamples() {
    let pool = OnTimeInputPlaceholders.pool(
      isRunning: true,
      isFinished: false,
      mode: .countdown,
      isPomodoroActive: false
    )
    for example in OnTimeInputPlaceholders.relativeWhenAdjustable {
      XCTAssertTrue(pool.contains(example), "Missing relative example: \(example)")
    }
    XCTAssertFalse(pool.contains("skip"))
  }

  func testRunningStopwatchExcludesRelativeAndSkip() {
    let pool = OnTimeInputPlaceholders.pool(
      isRunning: true,
      isFinished: false,
      mode: .stopwatch,
      isPomodoroActive: false
    )
    XCTAssertEqual(pool, OnTimeInputPlaceholders.defaults)
    XCTAssertFalse(pool.contains("+5 min"))
    XCTAssertFalse(pool.contains("skip"))
  }

  func testActivePomodoroAddsSkip() {
    let pool = OnTimeInputPlaceholders.pool(
      isRunning: true,
      isFinished: false,
      mode: .countdown,
      isPomodoroActive: true
    )
    XCTAssertTrue(pool.contains("skip"))
    for example in OnTimeInputPlaceholders.relativeWhenAdjustable {
      XCTAssertTrue(pool.contains(example))
    }
  }

  func testRelativePlaceholderFormsParse() {
    let model = OnTimeModel()
    defer { model.stop() }

    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+5 min") ?? 0, 5 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "-2 min") ?? 0, -2 * 60, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "+45 sec") ?? 0, 45, accuracy: 0.1)
    XCTAssertEqual(model.parsedRelativeAdjustment(from: "Add 30min") ?? 0, 30 * 60, accuracy: 0.1)
  }
}
