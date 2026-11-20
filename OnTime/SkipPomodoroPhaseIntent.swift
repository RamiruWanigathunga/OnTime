import AppIntents

struct SkipPomodoroPhaseIntent: AppIntent {
  static var title: LocalizedStringResource = "Skip Pomodoro Phase"
  static var description = IntentDescription(
    "Skip the current Pomodoro work or break phase and advance to the next.",
    categoryName: "Timer",
    searchKeywords: ["skip", "pomodoro", "break", "next phase"]
  )
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    guard model.skipPomodoroPhase() else {
      return .result(dialog: IntentDialog("No active Pomodoro phase to skip."))
    }
    return .result(dialog: IntentDialog("Skipped phase. \(OnTimeIntentSupport.statusDialog(for: model))"))
  }
}
