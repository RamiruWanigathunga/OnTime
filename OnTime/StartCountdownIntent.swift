import AppIntents

struct StartCountdownIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Countdown"
  static var description = IntentDescription(
    "Start an OnTime countdown using minutes and/or seconds.",
    categoryName: "Timer",
    searchKeywords: ["countdown", "timer", "minutes", "seconds", "start"]
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Minutes",
    description: "Minutes for the countdown.",
    default: 0
  )
  var minutes: Int

  @Parameter(
    title: "Seconds",
    description: "Additional seconds for the countdown.",
    default: 0
  )
  var seconds: Int

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let duration = OnTimeIntentSupport.durationSeconds(minutes: minutes, seconds: seconds)
    else {
      return .result(dialog: IntentDialog("Provide a duration greater than zero."))
    }
    let model = OnTimeIntentSupport.preparedModel()
    model.start(duration: duration, isTimeOfDay: false)
    let label = model.formatCompactDuration(duration)
    return .result(dialog: IntentDialog("Started a \(label) timer."))
  }
}
