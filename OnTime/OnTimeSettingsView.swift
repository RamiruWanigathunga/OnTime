import SwiftUI

struct OnTimeSettingsView: View {
  @ObservedObject var presentation: SettingsPresentationModel
  var onClose: () -> Void
  var onSelectAbout: () -> Void

  @State private var selectedPane: OnTimeSettingsPane = .general

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 10) {
        SettingsGlassPanel {
          VStack(spacing: 2) {
            ForEach(OnTimeSettingsPane.sidebarOrder) { pane in
              SettingsSidebarRow(
                title: pane.title,
                systemImage: pane.systemImage,
                tint: pane.tint,
                isSelected: selectedPane == pane && selectedPane != .about
              ) {
                selectedPane = pane
              }
            }
          }
        }
        .frame(width: 190)
        .settingsParallax(piece: .sidebar, presentation: presentation)

        SettingsGlassPanel {
          VStack(spacing: 2) {
            SettingsSidebarRow(
              title: OnTimeSettingsUtilityAction.about.title,
              systemImage: OnTimeSettingsUtilityAction.about.systemImage,
              tint: OnTimeSettingsUtilityAction.about.tint,
              isSelected: selectedPane == .about
            ) {
              selectedPane = .about
              onSelectAbout()
            }
            SettingsSidebarRow(
              title: OnTimeSettingsUtilityAction.close.title,
              systemImage: OnTimeSettingsUtilityAction.close.systemImage,
              tint: OnTimeSettingsUtilityAction.close.tint,
              isSelected: false,
              action: onClose
            )
          }
        }
        .frame(width: 190)
        .settingsParallax(piece: .utility, presentation: presentation)
      }

      // Top padding kept for the title; bottom is 0 so scrolled content can
      // travel to the panel edge instead of stopping above a dead bar.
      SettingsGlassPanel(
        contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 0, trailing: 14)
      ) {
        VStack(alignment: .leading, spacing: 12) {
          SettingsPaneHeader(
            title: selectedPane.title,
            systemImage: selectedPane.systemImage,
            tint: selectedPane.tint
          )
          paneContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(minWidth: 480, minHeight: 480)
      .settingsParallax(piece: .content, presentation: presentation)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // Catch clicks in the gaps between floating panels so they don’t fall
    // through to the desktop and instant-dismiss Settings. Keep fully clear
    // so no outer shade plate shows behind the three glass panels.
    .background(Color.clear)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var paneContent: some View {
    switch selectedPane {
    case .general:
      OnTimeGeneralSettingsPane()
    case .appearance:
      OnTimeAppearanceSettingsPane()
    case .pomodoro:
      OnTimeTimerSettingsPane()
    case .sound:
      OnTimeSoundSettingsPane()
    case .shortcuts:
      OnTimeShortcutsSettingsPane()
    case .about:
      OnTimeAboutSettingsPane()
    }
  }
}

private extension View {
  /// Per-piece vertical blur-slip driven by `motionProgress` (no scale/corner grow).
  func settingsParallax(
    piece: SettingsParallaxPiece,
    presentation: SettingsPresentationModel
  ) -> some View {
    let offset = presentation.offset(for: piece)
    return self
      .blur(radius: presentation.blur(for: piece))
      .opacity(presentation.opacity(for: piece))
      .offset(x: 0, y: offset.height)
      .animation(
        presentation.isDismissing
          ? .easeIn(duration: SettingsPresentationMotion.closeDuration)
            .delay(piece.dismissDelay)
          : .easeOut(duration: SettingsPresentationMotion.openDuration)
            .delay(piece.appearDelay),
        value: presentation.motionProgress
      )
  }
}

#Preview {
  OnTimeSettingsView(
    presentation: SettingsPresentationModel(),
    onClose: {},
    onSelectAbout: {}
  )
  .frame(width: 760, height: 560)
}
