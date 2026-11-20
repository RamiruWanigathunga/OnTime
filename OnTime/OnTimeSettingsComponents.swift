import AppKit
import SwiftUI

enum SettingsPanelStyle {
  static let cornerRadius: CGFloat = 20
  static let sectionCornerRadius: CGFloat = 12
  static let rowVerticalPadding: CGFloat = 10
  static let rowHorizontalPadding: CGFloat = 12
  /// Inset group fill — slightly darker than the Sequoia panel.
  static let sectionFill = Color.black.opacity(0.22)
  static let sectionStroke = Color.white.opacity(0.10)
  static let rowDivider = Color.white.opacity(0.08)
  static let titleFont = Font.system(size: 13, weight: .semibold)
  static let subtitleFont = Font.system(size: 11)
  static let sectionLabelFont = Font.system(size: 12, weight: .medium)
}

/// Sequoia-style behind-window vibrancy (not Liquid Glass).
struct SettingsSequoiaBackdrop: NSViewRepresentable {
  var cornerRadius: CGFloat

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.isEmphasized = true
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.masksToBounds = true
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = .hudWindow
    nsView.blendingMode = .behindWindow
    nsView.state = .active
    nsView.isEmphasized = true
    nsView.layer?.cornerRadius = cornerRadius
    nsView.layer?.cornerCurve = .continuous
    nsView.layer?.masksToBounds = true
  }
}

struct SettingsGlassPanel<Content: View>: View {
  var cornerRadius: CGFloat = SettingsPanelStyle.cornerRadius
  var contentPadding: EdgeInsets = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .padding(contentPadding)
      .background {
        SettingsSequoiaBackdrop(cornerRadius: cornerRadius)
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
      )
      // Tight shadow only — a large soft shadow filled the window margins and
      // read as an outer “shade plate” around the floating panels.
      .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 3)
  }
}

/// Compact inset group matching the inspiration’s sectioned cards.
struct SettingsSectionCard<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      content()
    }
    .background(
      RoundedRectangle(cornerRadius: SettingsPanelStyle.sectionCornerRadius, style: .continuous)
        .fill(SettingsPanelStyle.sectionFill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: SettingsPanelStyle.sectionCornerRadius, style: .continuous)
        .strokeBorder(SettingsPanelStyle.sectionStroke, lineWidth: 1)
    )
    .clipShape(
      RoundedRectangle(cornerRadius: SettingsPanelStyle.sectionCornerRadius, style: .continuous)
    )
  }
}

struct SettingsSectionLabel: View {
  let title: String

  var body: some View {
    Text(title)
      .font(SettingsPanelStyle.sectionLabelFont)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      // Match the section card’s row title inset.
      .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
      .padding(.bottom, 2)
  }
}

/// Title (+ optional subtitle) left-aligned; control trailing — Keeby-style row.
struct SettingsRow<Control: View>: View {
  let title: String
  var subtitle: String? = nil
  var showsDivider: Bool = true
  @ViewBuilder var control: () -> Control

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(SettingsPanelStyle.titleFont)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(SettingsPanelStyle.subtitleFont)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .multilineTextAlignment(.leading)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        control()
          .labelsHidden()
      }
      .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
      .padding(.vertical, SettingsPanelStyle.rowVerticalPadding)

      if showsDivider {
        Rectangle()
          .fill(SettingsPanelStyle.rowDivider)
          .frame(height: 1)
          .padding(.leading, SettingsPanelStyle.rowHorizontalPadding)
      }
    }
  }
}

struct SettingsToggleRow: View {
  let title: String
  var subtitle: String? = nil
  var showsDivider: Bool = true
  @Binding var isOn: Bool

  var body: some View {
    SettingsRow(title: title, subtitle: subtitle, showsDivider: showsDivider) {
      SettingsLiquidGlassToggle(isOn: $isOn)
    }
  }
}

/// Native switch at regular control size (system Liquid Glass chrome on macOS 26+).
struct SettingsLiquidGlassToggle: View {
  @Binding var isOn: Bool

  var body: some View {
    Toggle("", isOn: $isOn)
      .labelsHidden()
      .settingsSwitchStyle()
      .fixedSize()
  }
}

struct SettingsSidebarRow: View {
  let title: String
  let systemImage: String
  let tint: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 26, height: 26)
          .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background {
        if isSelected {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.14))
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct SettingsPaneHeader: View {
  let title: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      Text(title)
        .font(.system(size: 17, weight: .semibold))
      Spacer(minLength: 0)
    }
    // Match the section card’s inner row inset so the title lines up with row labels.
    .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
  }
}

struct SettingsErrorText: View {
  let message: String
  var body: some View {
    Text(message)
      .font(.system(size: 11))
      .foregroundStyle(.red)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, SettingsPanelStyle.rowHorizontalPadding)
      .padding(.vertical, 8)
  }
}

/// Shared scroll host so panes don’t stretch into tall empty form chrome.
struct SettingsPaneScroll<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      // Soft end inset only inside the scroll — viewport reaches the panel bottom.
      .padding(.bottom, 14)
    }
    .scrollIndicators(.hidden)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

extension View {
  /// Native macOS switch at regular control size (system Liquid Glass control chrome).
  func settingsSwitchStyle() -> some View {
    self
      .toggleStyle(.switch)
      .controlSize(.regular)
      .tint(.accentColor)
  }
}
