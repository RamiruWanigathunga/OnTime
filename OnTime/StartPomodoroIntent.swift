import AppIntents

struct StartPomodoroIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Pomodoro"
  static var description = IntentDescription(
    "Start an OnTime Pomodoro work session using your Pomodoro preferences.",
    categoryName: "Timer",
    searchKeywords: ["pomodoro", "focus", "work session", "pomo"]
  )
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    OnTimeIntentSupport.preparedModel().startPomodoro()
    return .result(dialog: IntentDialog("Started Pomodoro."))
  }
}
