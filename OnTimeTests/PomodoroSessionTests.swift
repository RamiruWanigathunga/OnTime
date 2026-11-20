import XCTest
@testable import OnTime

final class PomodoroSessionTests: XCTestCase {
  func testWorkBeforeFinalCycleStartsShortBreak() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 4))

    let duration = session.advanceToNextPhase()

    XCTAssertEqual(duration, 5 * 60)
    XCTAssertEqual(session.currentPhase, .shortBreak)
    XCTAssertEqual(session.currentCycle, 1)
    XCTAssertTrue(session.isActive)
  }

  func testFinalWorkCycleStartsLongBreak() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 1))

    let duration = session.advanceToNextPhase()

    XCTAssertEqual(duration, 15 * 60)
    XCTAssertEqual(session.currentPhase, .longBreak)
    XCTAssertEqual(session.currentCycle, 1)
  }

  func testShortBreakStartsNextWorkCycle() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 4))
    _ = session.advanceToNextPhase()

    let duration = session.advanceToNextPhase()

    XCTAssertEqual(duration, 25 * 60)
    XCTAssertEqual(session.currentPhase, .work)
    XCTAssertEqual(session.currentCycle, 2)
  }

  func testNonLoopingLongBreakEndsSession() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 1, shouldLoop: false))
    _ = session.advanceToNextPhase()
    let duration = session.advanceToNextPhase()

    XCTAssertEqual(duration, 0)
    XCTAssertFalse(session.isActive)
  }

  func testLoopingLongBreakStartsWorkCycleOne() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 1, shouldLoop: true))
    _ = session.advanceToNextPhase()
    let duration = session.advanceToNextPhase()

    XCTAssertEqual(duration, 25 * 60)
    XCTAssertEqual(session.currentPhase, .work)
    XCTAssertEqual(session.currentCycle, 1)
    XCTAssertTrue(session.isActive)
  }

  func testDisplayLabelsUseCompactMenuBarNotation() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 4))
    XCTAssertEqual(session.displayLabel(), "W 1/4")

    _ = session.advanceToNextPhase()
    XCTAssertEqual(session.displayLabel(), "B 1/4")

    _ = session.advanceToNextPhase()
    XCTAssertEqual(session.displayLabel(), "W 2/4")
  }

  func testPhaseDescriptionsUseFractionsOnlyForWork() {
    var session = PomodoroSession(from: preferences(cyclesPerSet: 4))
    XCTAssertEqual(session.phaseDescription(includeCycle: true), "Work cycle 1/4")

    _ = session.advanceToNextPhase()
    XCTAssertEqual(session.phaseDescription(includeCycle: false), "Short break")
  }

  private func preferences(
    cyclesPerSet: Int,
    shouldLoop: Bool = false
  ) -> PomodoroPreferences {
    let defaults = UserDefaults.standard
    defaults.set(25, forKey: OnTimeSettingsKeys.pomodoroWorkMinutes)
    defaults.set(5, forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes)
    defaults.set(15, forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes)
    defaults.set(cyclesPerSet, forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet)
    defaults.set(shouldLoop, forKey: OnTimeSettingsKeys.pomodoroShouldLoop)
    defer {
      defaults.removeObject(forKey: OnTimeSettingsKeys.pomodoroWorkMinutes)
      defaults.removeObject(forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes)
      defaults.removeObject(forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes)
      defaults.removeObject(forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet)
      defaults.removeObject(forKey: OnTimeSettingsKeys.pomodoroShouldLoop)
    }
    return PomodoroPreferences()
  }
}
