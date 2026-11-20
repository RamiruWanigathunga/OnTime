import XCTest
@testable import OnTime

final class PomodoroPreferencesTests: XCTestCase {
  override func tearDown() {
    let defaults = UserDefaults.standard
    [
      OnTimeSettingsKeys.pomodoroWorkMinutes,
      OnTimeSettingsKeys.pomodoroShortBreakMinutes,
      OnTimeSettingsKeys.pomodoroLongBreakMinutes,
      OnTimeSettingsKeys.pomodoroCyclesPerSet,
      OnTimeSettingsKeys.pomodoroShouldLoop,
    ].forEach { defaults.removeObject(forKey: $0) }
    super.tearDown()
  }

  func testDefaults() {
    let preferences = PomodoroPreferences()

    XCTAssertEqual(preferences.workMinutes, PomodoroDefaults.workMinutes)
    XCTAssertEqual(preferences.shortBreakMinutes, PomodoroDefaults.shortBreakMinutes)
    XCTAssertEqual(preferences.longBreakMinutes, PomodoroDefaults.longBreakMinutes)
    XCTAssertEqual(preferences.cyclesPerSet, PomodoroDefaults.cyclesPerSet)
    XCTAssertFalse(preferences.shouldLoop)
  }

  func testDurationValuesClampToEightHours() {
    let defaults = UserDefaults.standard
    defaults.set(PomodoroDefaults.maximumDurationMinutes + 1, forKey: OnTimeSettingsKeys.pomodoroWorkMinutes)
    defaults.set(PomodoroDefaults.maximumDurationMinutes + 1, forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes)
    defaults.set(PomodoroDefaults.maximumDurationMinutes + 1, forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes)

    let preferences = PomodoroPreferences()

    XCTAssertEqual(preferences.workMinutes, PomodoroDefaults.maximumDurationMinutes)
    XCTAssertEqual(preferences.shortBreakMinutes, PomodoroDefaults.maximumDurationMinutes)
    XCTAssertEqual(preferences.longBreakMinutes, PomodoroDefaults.maximumDurationMinutes)
  }

  func testCycleCountClampsToMaximum() {
    UserDefaults.standard.set(
      PomodoroDefaults.maximumCyclesPerSet + 1,
      forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet
    )

    XCTAssertEqual(PomodoroPreferences().cyclesPerSet, PomodoroDefaults.maximumCyclesPerSet)
  }

  func testValuesClampToMinimumOne() {
    let defaults = UserDefaults.standard
    defaults.set(0, forKey: OnTimeSettingsKeys.pomodoroWorkMinutes)
    defaults.set(-1, forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes)
    defaults.set(0, forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes)
    defaults.set(0, forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet)

    let preferences = PomodoroPreferences()

    XCTAssertEqual(preferences.workMinutes, 1)
    XCTAssertEqual(preferences.shortBreakMinutes, 1)
    XCTAssertEqual(preferences.longBreakMinutes, 1)
    XCTAssertEqual(preferences.cyclesPerSet, 1)
  }
}
