import AppIntents

struct StartStopwatchIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Stopwatch"
  static var description = IntentDescription(
    "Start the OnTime stopwatch.",
    categoryName: "Timer",
    searchKeywords: ["stopwatch", "elapsed", "count up"]
  )
  static var openAppWhenRun: Bool = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    OnTimeIntentSupport.preparedModel().startStopwatch()
    return .result(dialog: IntentDialog("Started stopwatch."))
  }
}
