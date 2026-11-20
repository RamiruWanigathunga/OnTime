import AppIntents

struct PauseTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Pause Timer"
  static var description = IntentDescription(
    "Pause the running OnTime countdown, Pomodoro, or stopwatch.",
    categoryName: "Timer",
    searchKeywords: ["pause", "timer", "hold"]
  )
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    guard model.isRunning, !model.isPaused, !model.isFinished else {
      return .result(dialog: IntentDialog("Nothing to pause."))
    }
    if model.isTimeOfDayCountdown {
      return .result(dialog: IntentDialog("Time-of-day countdowns can't be paused."))
    }
    model.pause()
    return .result(dialog: IntentDialog("Paused. \(OnTimeIntentSupport.statusDialog(for: model))"))
  }
}
