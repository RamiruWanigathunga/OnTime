import Foundation

enum OnTimeURLCommand: String {
  case start
  case add
  case subtract
  case pomodoro
  case stopwatch
  case pause
  case resume
  case toggle
  case skip
  case stop
  case clear
}

struct OnTimeURLAction: Equatable {
  let command: OnTimeURLCommand
  let duration: TimeInterval?
}

enum OnTimeURLHandler {
  static func parse(_ url: URL) -> OnTimeURLAction? {
    guard let scheme = url.scheme, scheme.caseInsensitiveCompare("ontime") == .orderedSame else {
      return nil
    }
    let host = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
      .lowercased()
    guard let command = OnTimeURLCommand(rawValue: host) else { return nil }

    let duration: TimeInterval?
    switch command {
    case .start, .add, .subtract:
      duration = durationFromQuery(url)
    default:
      duration = nil
    }
    return OnTimeURLAction(command: command, duration: duration)
  }

  @discardableResult
  static func perform(_ action: OnTimeURLAction, on model: OnTimeModel) -> Bool {
    switch action.command {
    case .start:
      guard let duration = action.duration, duration > 0 else { return false }
      model.start(duration: duration, isTimeOfDay: false)
      return true
    case .add:
      guard let duration = action.duration, duration > 0 else { return false }
      return model.applyRelativeAdjustment(duration)
    case .subtract:
      guard let duration = action.duration, duration > 0 else { return false }
      return model.applyRelativeAdjustment(-duration)
    case .pomodoro:
      model.startPomodoro()
      return true
    case .stopwatch:
      model.startStopwatch()
      return true
    case .pause:
      model.pause()
      return true
    case .resume:
      model.resume()
      return true
    case .toggle:
      if model.isRunning {
        if model.isPaused { model.resume() } else { model.pause() }
      }
      return true
    case .skip:
      return model.skipPomodoroPhase()
    case .stop, .clear:
      model.stop()
      return true
    }
  }

  private static func durationFromQuery(_ url: URL) -> TimeInterval? {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let keys = ["duration", "time", "d", "t"]
    guard let raw = items.first(where: { keys.contains($0.name.lowercased()) })?.value?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return nil }

    let model = OnTimeModel()
    if let relative = model.parsedRelativeAdjustment(from: raw.lowercased()) {
      return abs(relative)
    }
    let duration = model.parsedDuration(from: raw.lowercased())
    return duration > 0 ? duration : nil
  }
}
