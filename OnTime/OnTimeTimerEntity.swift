import AppIntents
import Foundation

/// App Entity exposing the live timer session to Shortcuts and Apple Intelligence.
struct OnTimeTimerEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "OnTime Timer")
  static var defaultQuery = OnTimeTimerEntityQuery()

  var id: String
  var modeLabel: String
  var displayTime: String
  var isPaused: Bool
  var isRunning: Bool

  var displayRepresentation: DisplayRepresentation {
    if !isRunning {
      return DisplayRepresentation(
        title: LocalizedStringResource(stringLiteral: "Idle"),
        subtitle: LocalizedStringResource(stringLiteral: "No timer running")
      )
    }
    let pauseNote = isPaused ? " · paused" : ""
    return DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: "\(modeLabel)\(pauseNote)"),
      subtitle: LocalizedStringResource(stringLiteral: displayTime)
    )
  }

  @MainActor
  static func current(from model: OnTimeModel) -> OnTimeTimerEntity {
    OnTimeTimerEntity(
      id: "current",
      modeLabel: OnTimeIntentSupport.modeLabel(for: model),
      displayTime: model.isRunning ? model.formattedRemaining : "—",
      isPaused: model.isPaused,
      isRunning: model.isRunning && !model.isFinished
    )
  }

  @MainActor
  static func current() -> OnTimeTimerEntity {
    current(from: OnTimeModel.shared)
  }
}

struct OnTimeTimerEntityQuery: EntityQuery {
  @MainActor
  func entities(for identifiers: [OnTimeTimerEntity.ID]) async throws -> [OnTimeTimerEntity] {
    let current = OnTimeTimerEntity.current()
    return identifiers.contains(current.id) ? [current] : []
  }

  @MainActor
  func suggestedEntities() async throws -> [OnTimeTimerEntity] {
    [OnTimeTimerEntity.current()]
  }
}
