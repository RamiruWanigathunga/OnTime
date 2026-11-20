import AppIntents

struct StopTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Stop Timer"
  static var description = IntentDescription(
    "Stop and clear the current OnTime timer.",
    categoryName: "Timer",
    searchKeywords: ["stop", "clear", "cancel", "timer"]
  )
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    guard model.isRunning || model.isFinished else {
      return .result(dialog: IntentDialog("No timer to stop."))
    }
    model.stop()
    return .result(dialog: IntentDialog("Timer cleared."))
  }
}
