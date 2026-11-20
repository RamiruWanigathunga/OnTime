import AppIntents

struct ResumeTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Resume Timer"
  static var description = IntentDescription(
    "Resume a paused OnTime timer.",
    categoryName: "Timer",
    searchKeywords: ["resume", "continue", "unpause", "timer"]
  )
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    guard model.isRunning, model.isPaused, !model.isFinished else {
      return .result(dialog: IntentDialog("Nothing to resume."))
    }
    model.resume()
    return .result(dialog: IntentDialog("Resumed. \(OnTimeIntentSupport.statusDialog(for: model))"))
  }
}
