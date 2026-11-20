import ServiceManagement
import SwiftUI
import UserNotifications

struct OnTimeGeneralSettingsPane: View {
  @AppStorage(OnTimeSettingsKeys.showNotifications) private var showNotifications = false
  @AppStorage(OnTimeSettingsKeys.stretchToSetTimer) private var stretchToSetTimer =
    StretchTimerDefaults.isEnabled
  @AppStorage(OnTimeSettingsKeys.defaultUnit) private var defaultUnit = DefaultTimeUnit.default
    .rawValue

  @State private var launchAtLogin = false
  @State private var isUpdatingLaunchAtLogin = false
  @State private var launchAtLoginError: String?
  @State private var showNotificationsError: String?

  var body: some View {
    SettingsPaneScroll {
      SettingsSectionCard {
        SettingsToggleRow(
          title: "Launch OnTime at login",
          subtitle: "Starts OnTime automatically when your Mac starts.",
          isOn: $launchAtLogin
        )
        .onChange(of: launchAtLogin) { _, newValue in
          guard !isUpdatingLaunchAtLogin else { return }
          setLaunchAtLogin(newValue)
        }

        SettingsToggleRow(
          title: "Show notifications",
          subtitle: "Banner when a timer finishes.",
          isOn: $showNotifications
        )
        .onChange(of: showNotifications) { _, newValue in
          handleShowNotificationsChange(newValue)
        }

        SettingsToggleRow(
          title: "Stretch menu bar icon to set timer",
          subtitle:
            "Drag down from the menu bar icon to set a countdown. Hold Option (⌥) for seconds.",
          isOn: $stretchToSetTimer
        )

        if launchAtLoginError != nil || showNotificationsError != nil {
          VStack(alignment: .leading, spacing: 4) {
            if let launchAtLoginError {
              SettingsErrorText(message: launchAtLoginError)
            }
            if let showNotificationsError {
              SettingsErrorText(message: showNotificationsError)
            }
          }
          Rectangle()
            .fill(SettingsPanelStyle.rowDivider)
            .frame(height: 1)
            .padding(.leading, SettingsPanelStyle.rowHorizontalPadding)
        }

        SettingsRow(title: "Default unit", subtitle: "Used when a duration has no unit.", showsDivider: false) {
          Picker("", selection: $defaultUnit) {
            ForEach(DefaultTimeUnit.allCases) { unit in
              Text(unit.displayName).tag(unit.rawValue)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .fixedSize()
        }
      }
    }
    .onAppear {
      refreshLaunchAtLoginState()
      refreshNotificationAuthorization()
    }
  }

  private func refreshLaunchAtLoginState() {
    guard #available(macOS 13.0, *) else { return }
    isUpdatingLaunchAtLogin = true
    launchAtLogin = SMAppService.mainApp.status == .enabled
    isUpdatingLaunchAtLogin = false
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    guard #available(macOS 13.0, *) else { return }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLoginError = nil
    } catch {
      launchAtLoginError = "Could not update login item."
    }
    refreshLaunchAtLoginState()
  }

  private func refreshNotificationAuthorization() {
    guard showNotifications else { return }
    OnTimeNotificationAuth.getSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        showNotificationsError = nil
      case .notDetermined:
        break
      case .denied:
        showNotifications = false
        showNotificationsError =
          "Notifications are off in System Settings. Open Notifications and enable OnTime."
      @unknown default:
        showNotifications = false
        showNotificationsError = "Notifications are unavailable."
      }
    }
  }

  private func handleShowNotificationsChange(_ enabled: Bool) {
    guard enabled else {
      showNotificationsError = nil
      return
    }

    OnTimeNotificationAuth.getSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        showNotificationsError = nil
      case .notDetermined:
        // Accessory apps often never show the permission sheet without this.
        OnTimeNotificationAuth.requestAuthorization { granted in
          if granted {
            showNotificationsError = nil
          } else {
            showNotifications = false
            showNotificationsError =
              "Notifications were not allowed. You can enable OnTime in System Settings."
            OnTimeNotificationAuth.openSystemSettings()
          }
        }
      case .denied:
        showNotifications = false
        showNotificationsError =
          "Notifications are off in System Settings. Opening Notifications…"
        OnTimeNotificationAuth.openSystemSettings()
      @unknown default:
        showNotifications = false
        showNotificationsError = "Notifications are unavailable."
      }
    }
  }
}
