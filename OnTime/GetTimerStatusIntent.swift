import AppIntents

struct GetTimerStatusIntent: AppIntent {
  static var title: LocalizedStringResource = "Get Timer Status"
  static var description = IntentDescription(
    "Report the current OnTime mode and remaining or elapsed time.",
    categoryName: "Timer",
    searchKeywords: ["status", "remaining", "how much time", "left", "timer", "elapsed"]
  )
  static var openAppWhenRun: Bool = false

  static var parameterSummary: some ParameterSummary {
    Summary("Get timer status from OnTime")
  }

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    let value = OnTimeIntentSupport.statusValue(for: model)
    let spoken = OnTimeIntentSupport.statusDialog(for: model)
    _ = OnTimeTimerEntity.current(from: model)
    return .result(value: value, dialog: IntentDialog(stringLiteral: spoken))
  }
}
