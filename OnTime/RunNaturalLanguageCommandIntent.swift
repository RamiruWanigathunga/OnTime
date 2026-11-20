import AppIntents

struct RunNaturalLanguageCommandIntent: AppIntent {
  static var title: LocalizedStringResource = "Run Timer Command"
  static var description = IntentDescription(
    "Run a natural-language OnTime command such as 25m, 1h 30m, 10pm, +5m, pomo, or sw.",
    categoryName: "Timer",
    searchKeywords: ["timer", "countdown", "pomodoro", "stopwatch", "natural language"]
  )
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "Command",
    description: "Natural-language timer input (for example 25m, 10pm, +5m, pomo, sw).",
    requestValueDialog: IntentDialog("What should OnTime do?")
  )
  var command: String

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = OnTimeIntentSupport.preparedModel()
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw $command.needsValueError(IntentDialog("What should OnTime do?"))
    }
    let preview = model.previewForInput(trimmed)
    model.inputDuration = trimmed
    let ok = model.startFromInputs()
    guard ok else {
      return .result(dialog: IntentDialog("I couldn't understand \(trimmed)."))
    }
    let spoken = preview ?? OnTimeIntentSupport.statusDialog(for: model)
    return .result(dialog: IntentDialog(stringLiteral: spoken))
  }
}
