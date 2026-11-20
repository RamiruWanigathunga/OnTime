import AppKit
import SwiftUI

struct OnTimeAboutSettingsPane: View {
  private var versionString: String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    return "Version \(v) (\(b))"
  }

  var body: some View {
    SettingsPaneScroll {
      SettingsSectionCard {
        HStack(spacing: 12) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 52, height: 52)
          VStack(alignment: .leading, spacing: 2) {
            Text("OnTime")
              .font(SettingsPanelStyle.titleFont)
            Text("Privacy-first menu bar timer")
              .font(SettingsPanelStyle.subtitleFont)
              .foregroundStyle(.secondary)
            Text(versionString)
              .font(SettingsPanelStyle.subtitleFont)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
        .padding(.vertical, 12)
      }

      SettingsSectionCard {
        VStack(alignment: .leading, spacing: 2) {
          Text("About")
            .font(SettingsPanelStyle.titleFont)
          Text("OnTime is a privacy-first countdown and Pomodoro timer for macOS.")
            .font(SettingsPanelStyle.subtitleFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
        .padding(.vertical, SettingsPanelStyle.rowVerticalPadding)

        Rectangle()
          .fill(SettingsPanelStyle.rowDivider)
          .frame(height: 1)
          .padding(.leading, SettingsPanelStyle.rowHorizontalPadding)

        SettingsRow(title: "Updates") {
          Button("Check for Updates…") {
            (NSApp.delegate as? AppDelegate)?.checkForUpdatesFromSettings()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        SettingsRow(title: "Quit OnTime", showsDivider: false) {
          Button("Quit") { NSApp.terminate(nil) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("q", modifiers: [.command])
        }
      }
    }
  }
}
