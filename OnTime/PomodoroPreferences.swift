import Foundation

struct PomodoroPreferences {
  let workMinutes: Int
  let shortBreakMinutes: Int
  let longBreakMinutes: Int
  let cyclesPerSet: Int
  let shouldLoop: Bool

  init() {
    let defaults = UserDefaults.standard
    self.workMinutes = min(
      PomodoroDefaults.maximumDurationMinutes,
      max(
        1,
      defaults.object(forKey: OnTimeSettingsKeys.pomodoroWorkMinutes) == nil
        ? PomodoroDefaults.workMinutes
        : defaults.integer(forKey: OnTimeSettingsKeys.pomodoroWorkMinutes)
      )
    )
    self.shortBreakMinutes = min(
      PomodoroDefaults.maximumDurationMinutes,
      max(
        1,
      defaults.object(forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes) == nil
        ? PomodoroDefaults.shortBreakMinutes
        : defaults.integer(forKey: OnTimeSettingsKeys.pomodoroShortBreakMinutes)
      )
    )
    self.longBreakMinutes = min(
      PomodoroDefaults.maximumDurationMinutes,
      max(
        1,
      defaults.object(forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes) == nil
        ? PomodoroDefaults.longBreakMinutes
        : defaults.integer(forKey: OnTimeSettingsKeys.pomodoroLongBreakMinutes)
      )
    )
    self.cyclesPerSet = min(
      PomodoroDefaults.maximumCyclesPerSet,
      max(
        1,
      defaults.object(forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet) == nil
        ? PomodoroDefaults.cyclesPerSet
        : defaults.integer(forKey: OnTimeSettingsKeys.pomodoroCyclesPerSet)
      )
    )
    self.shouldLoop = defaults.bool(forKey: OnTimeSettingsKeys.pomodoroShouldLoop)
  }
}
