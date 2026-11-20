import SwiftUI

struct OnTimeAppearanceSettingsPane: View {
  @AppStorage(OnTimeSettingsKeys.menuBarIconSize) private var menuBarIconSize = MenuBarIconSize
    .default.rawValue
  @AppStorage(OnTimeSettingsKeys.menuBarIcon) private var menuBarIcon = MenuBarIcon.default.rawValue
  @AppStorage(OnTimeSettingsKeys.menuButtonSize) private var menuButtonSize = MenuButtonSize.default
    .rawValue
  @AppStorage(OnTimeSettingsKeys.menuButtonBrightness) private var menuButtonBrightness =
    MenuButtonBrightness.default.rawValue
  @AppStorage(OnTimeSettingsKeys.menuBarStyle) private var menuBarStyle = MenuBarStyle.default.rawValue
  @AppStorage(OnTimeSettingsKeys.menuBarFontStyle) private var menuBarFontStyle =
    MenuBarFontStyle.default.rawValue
  @AppStorage(OnTimeSettingsKeys.displayPrecision) private var displayPrecision =
    DisplayPrecision.default.rawValue

  var body: some View {
    SettingsPaneScroll {
      SettingsSectionCard {
        SettingsRow(title: "Menu bar icon") {
          Picker("", selection: $menuBarIcon) {
            ForEach(MenuBarIcon.allCases) { icon in
              Text(icon.displayName).tag(icon.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        SettingsRow(title: "Icon size") {
          Picker("", selection: $menuBarIconSize) {
            ForEach(MenuBarIconSize.allCases) { size in
              Text(size.displayName).tag(size.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        SettingsRow(title: "Button size") {
          Picker("", selection: $menuButtonSize) {
            ForEach(MenuButtonSize.allCases) { size in
              Text(size.displayName).tag(size.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        SettingsRow(title: "Button brightness") {
          Picker("", selection: $menuButtonBrightness) {
            ForEach(MenuButtonBrightness.allCases) { brightness in
              Text(brightness.displayName).tag(brightness.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        SettingsRow(title: "Menu bar style") {
          Picker("", selection: $menuBarStyle) {
            ForEach(MenuBarStyle.allCases) { style in
              Text(style.displayName).tag(style.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        SettingsRow(title: "Menu bar font") {
          Picker("", selection: $menuBarFontStyle) {
            ForEach(MenuBarFontStyle.allCases) { style in
              Text(style.displayName).tag(style.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }

        SettingsRow(
          title: "Display precision",
          subtitle: "Countdown, Pomodoro, and stopwatch. Seconds is MM:SS; Tenths is MM:SS.T.",
          showsDivider: false
        ) {
          Picker("", selection: $displayPrecision) {
            ForEach(DisplayPrecision.allCases) { precision in
              Text(precision.displayName).tag(precision.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }
      }
    }
    .onAppear {
      DisplayPrecision.migrateIfNeeded()
      if DisplayPrecision(rawValue: displayPrecision) == nil {
        displayPrecision = DisplayPrecision.current().rawValue
      }
      if MenuBarIconSize(rawValue: menuBarIconSize) == nil {
        menuBarIconSize = MenuBarIconSize.default.rawValue
      }
      if MenuBarIcon(rawValue: menuBarIcon) == nil {
        menuBarIcon = MenuBarIcon.default.rawValue
      }
      if MenuButtonSize(rawValue: menuButtonSize) == nil {
        menuButtonSize = MenuButtonSize.default.rawValue
      }
      if MenuButtonBrightness(rawValue: menuButtonBrightness) == nil {
        menuButtonBrightness = MenuButtonBrightness.default.rawValue
      }
    }
  }
}
