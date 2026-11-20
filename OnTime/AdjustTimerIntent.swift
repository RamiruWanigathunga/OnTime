import AppIntents

struct AdjustTimerIntent: AppIntent {
  static var title: LocalizedStringResource = "Adjust Timer"
  static var description = IntentDescription(
    "Add or subtract time from the current OnTime countdown, or start a new timer when idle.",
    categoryName: "Timer",
    searchKeywords: ["add time", "subtract", "extend", "adjust", "timer"]
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Minutes",
    description: "Minutes to add or subtract.",
    default: 0
  )
  var minutes: Int

  @Parameter(
    title: "Seconds",
    description: "Seconds to add or subtract.",
    default: 0
  )
  var seconds: Int

  @Parameter(
    title: "Subtract",
    description: "When true, subtract the duration instead of adding it.",
    default: false
  )
  var subtract: Bool

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard
      let delta = OnTimeIntentSupport.adjustmentSeconds(
        minutes: minutes, seconds: seconds, subtract: subtract)
    else {
      return .result(dialog: IntentDialog("Provide a duration greater than zero."))
    }
    let model = OnTimeIntentSupport.preparedModel()
    let ok = model.applyRelativeAdjustment(delta)
    guard ok else {
      return .result(dialog: IntentDialog("Couldn't adjust the timer."))
    }
    let magnitude = model.formatCompactDuration(abs(delta))
    if delta >= 0 {
      return .result(dialog: IntentDialog("Added \(magnitude). \(OnTimeIntentSupport.statusDialog(for: model))"))
    }
    return .result(dialog: IntentDialog("Subtracted \(magnitude). \(OnTimeIntentSupport.statusDialog(for: model))"))
  }
}
