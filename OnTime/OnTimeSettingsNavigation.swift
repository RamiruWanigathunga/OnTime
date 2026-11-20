import SwiftUI

enum OnTimeSettingsPane: String, CaseIterable, Identifiable, Hashable {
  case general
  case appearance
  case pomodoro
  case sound
  case shortcuts
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .appearance: return "Appearance"
    case .pomodoro: return "Pomodoro"
    case .sound: return "Sound"
    case .shortcuts: return "Shortcuts"
    case .about: return "About"
    }
  }

  var systemImage: String {
    switch self {
    case .general: return "gearshape.fill"
    case .appearance: return "paintpalette.fill"
    case .pomodoro: return "timer"
    case .sound: return "speaker.wave.2.fill"
    case .shortcuts: return "keyboard"
    case .about: return "info.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .general: return Color(red: 0.55, green: 0.56, blue: 0.60)
    case .appearance: return Color(red: 0.20, green: 0.62, blue: 0.98)
    case .pomodoro: return Color(red: 1.00, green: 0.35, blue: 0.24)
    case .sound: return Color(red: 0.96, green: 0.24, blue: 0.36)
    case .shortcuts: return Color(red: 0.45, green: 0.45, blue: 0.50)
    case .about: return Color(red: 0.20, green: 0.48, blue: 0.96)
    }
  }

  /// Top nav only — About lives in the utility stack.
  static var sidebarOrder: [OnTimeSettingsPane] {
    [.general, .appearance, .pomodoro, .sound, .shortcuts]
  }
}

enum OnTimeSettingsUtilityAction: String, CaseIterable, Identifiable {
  case about
  case close

  var id: String { rawValue }

  var title: String {
    switch self {
    case .about: return "About"
    case .close: return "Close"
    }
  }

  var systemImage: String {
    switch self {
    case .about: return "info.circle.fill"
    case .close: return "xmark"
    }
  }

  var tint: Color {
    switch self {
    case .about: return Color(red: 0.20, green: 0.48, blue: 0.96)
    case .close: return Color(red: 0.96, green: 0.28, blue: 0.28)
    }
  }
}