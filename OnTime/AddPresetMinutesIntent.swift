import AppIntents

/// Siri App Shortcut for adding a preset number of minutes to the timer.
struct AddPresetMinutesIntent: AppIntent {
  static var title: LocalizedStringResource = "Add Minutes"
  static var description = IntentDescription(
    "Add a preset number of minutes to the current OnTime timer, or start one when idle.",
    categoryName: "Timer",
    searchKeywords: ["add time", "extend", "minutes", "adjust"]
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Minutes",
    description: "Minutes to add."
  )
  var minutes: OnTimeMinutePreset

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    let delta = minutes.timeInterval
    let ok = model.applyRelativeAdjustment(delta)
    guard ok else {
      return .result(dialog: IntentDialog("Couldn't adjust the timer."))
    }
    let magnitude = model.formatCompactDuration(delta)
    return .result(
      dialog: IntentDialog("Added \(magnitude). \(OnTimeIntentSupport.statusDialog(for: model))"))
  }
}
