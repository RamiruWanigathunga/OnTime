import AppIntents

/// App Shortcut–compatible duration presets (App Shortcuts only allow AppEnum/AppEntity params).
enum OnTimeMinutePreset: Int, AppEnum {
  case five = 5
  case ten = 10
  case fifteen = 15
  case twentyFive = 25
  case thirty = 30
  case fortyFive = 45
  case sixty = 60

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Minutes")

  static var caseDisplayRepresentations: [OnTimeMinutePreset: DisplayRepresentation] = [
    .five: "5",
    .ten: "10",
    .fifteen: "15",
    .twentyFive: "25",
    .thirty: "30",
    .fortyFive: "45",
    .sixty: "60",
  ]

  var timeInterval: TimeInterval { TimeInterval(rawValue * 60) }
}
