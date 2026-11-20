import Foundation

/// Shared helpers for App Intents — keep dialog/parameter mapping testable without Siri.
enum OnTimeIntentSupport {
  /// Always use the menu-bar singleton and ensure JSONL logging is wired (cold Siri launches).
  @MainActor
  static func preparedModel() -> OnTimeModel {
    let model = OnTimeModel.shared
    if model.eventLogger == nil {
      model.eventLogger = { event, fields in
        OnTimeLogger.shared.log(event: event, fields: fields)
      }
    }
    return model
  }

  static func durationSeconds(minutes: Int?, seconds: Int?) -> TimeInterval? {
    let totalMinutes = max(0, minutes ?? 0)
    let totalSeconds = max(0, seconds ?? 0)
    let combined = TimeInterval(totalMinutes * 60 + totalSeconds)
    return combined > 0 ? combined : nil
  }

  static func adjustmentSeconds(minutes: Int?, seconds: Int?, subtract: Bool) -> TimeInterval? {
    guard let magnitude = durationSeconds(minutes: minutes, seconds: seconds) else { return nil }
    return subtract ? -magnitude : magnitude
  }

  @MainActor
  static func modeLabel(for model: OnTimeModel) -> String {
    if let session = model.pomodoroSession, session.isActive {
      return model.pomodoroLabel.isEmpty ? "Pomodoro" : model.pomodoroLabel
    }
    switch model.mode {
    case .stopwatch:
      return "Stopwatch"
    case .countdown:
      return model.isTimeOfDayCountdown ? "Until time" : "Countdown"
    }
  }

  /// Compact machine-readable status for Shortcuts `ReturnsValue`.
  @MainActor
  static func statusValue(for model: OnTimeModel) -> String {
    guard model.isRunning else { return "Idle" }
    let mode = modeLabel(for: model)
    let paused = model.isPaused ? " paused" : ""
    if model.isFinished {
      return "\(mode) finished"
    }
    switch model.mode {
    case .stopwatch:
      return "\(mode)\(paused) \(model.formattedRemaining)"
    case .countdown:
      return "\(mode)\(paused) \(model.formattedRemaining) remaining"
    }
  }

  /// Spoken dialog for Siri / “how much time is left”.
  @MainActor
  static func statusDialog(for model: OnTimeModel) -> String {
    guard model.isRunning else {
      return "No timer is running."
    }
    if model.isFinished {
      return "The timer has finished."
    }
    let time = model.formattedRemaining
    if model.isPaused {
      switch model.mode {
      case .stopwatch:
        return "Stopwatch is paused at \(time)."
      case .countdown:
        return "Timer is paused with \(time) remaining."
      }
    }
    if let session = model.pomodoroSession, session.isActive {
      let phase = model.pomodoroLabel.isEmpty ? "Pomodoro" : model.pomodoroLabel
      return "\(phase) has \(time) remaining."
    }
    switch model.mode {
    case .stopwatch:
      return "Stopwatch is at \(time)."
    case .countdown:
      return "\(time) remaining."
    }
  }
}
