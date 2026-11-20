import AppIntents

/// Siri App Shortcut entry point using an AppEnum duration (Int/String cannot appear in phrases).
struct StartPresetCountdownIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Preset Countdown"
  static var description = IntentDescription(
    "Start an OnTime countdown for a common preset duration.",
    categoryName: "Timer",
    searchKeywords: ["countdown", "timer", "minutes", "preset", "start"]
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Minutes",
    description: "Preset countdown length in minutes."
  )
  var minutes: OnTimeMinutePreset

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    let duration = minutes.timeInterval
    model.start(duration: duration, isTimeOfDay: false)
    let label = model.formatCompactDuration(duration)
    return .result(dialog: IntentDialog("Started a \(label) timer."))
  }
}
