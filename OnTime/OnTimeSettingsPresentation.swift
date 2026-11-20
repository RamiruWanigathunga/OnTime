import CoreGraphics
import Foundation

enum SettingsPresentationPhase: Equatable {
  case hidden
  case appearing
  case visible
  case dismissing
}

/// Experimental three-piece blur-slide with parallax stagger.
enum SettingsPresentationMotion {
  static let openDuration: TimeInterval = 0.36
  static let closeDuration: TimeInterval = 0.30
  /// Longest per-piece stagger; orderOut waits past this.
  static let staggerMax: TimeInterval = 0.12
  /// Shared soft scale floor while pieces are mid-flight.
  static let compressedScale: Double = 0.97
  static let blurredRadius: Double = 22
}

/// The three floating Settings surfaces — each rides a different offset/blur curve.
enum SettingsParallaxPiece: CaseIterable {
  case sidebar
  case utility
  case content

  /// Enter offset at progress 0 — positive Y only (straight up from below).
  /// No X drift / scale — those read as a corner grow instead of a slip-up.
  var enterOffset: CGSize {
    switch self {
    case .sidebar: return CGSize(width: 0, height: 18)
    case .utility: return CGSize(width: 0, height: 24)
    case .content: return CGSize(width: 0, height: 30)
    }
  }

  var enterBlur: Double {
    switch self {
    case .sidebar: return 22
    case .utility: return 26
    case .content: return 30
    }
  }

  /// Appearance order: tabs → About/Close → settings content.
  var appearDelay: TimeInterval {
    switch self {
    case .sidebar: return 0
    case .utility: return 0.05
    case .content: return 0.10
    }
  }

  /// Reverse on dismiss: content sinks first, tabs last.
  var dismissDelay: TimeInterval {
    switch self {
    case .content: return 0
    case .utility: return 0.05
    case .sidebar: return 0.10
    }
  }
}

@MainActor
final class SettingsPresentationModel: ObservableObject {
  @Published private(set) var phase: SettingsPresentationPhase = .hidden
  /// 0 = off-screen / blurred pieces, 1 = settled.
  @Published var motionProgress: Double = 0
  @Published var opacity: Double = 0
  @Published var blurRadius: Double = SettingsPresentationMotion.blurredRadius
  @Published var scale: Double = SettingsPresentationMotion.compressedScale

  var isDismissing: Bool { phase == .dismissing }

  func resetForShow() {
    phase = .hidden
    motionProgress = 0
    opacity = 0
    blurRadius = SettingsPresentationMotion.blurredRadius
    scale = SettingsPresentationMotion.compressedScale
  }

  func beginAppear() {
    phase = .appearing
  }

  func applySettledAppearance() {
    motionProgress = 1
    opacity = 1
    blurRadius = 0
    scale = 1
  }

  func applyDismissAppearance() {
    motionProgress = 0
    opacity = 0
    blurRadius = SettingsPresentationMotion.blurredRadius
    scale = SettingsPresentationMotion.compressedScale
  }

  func markVisible() {
    guard phase == .appearing || phase == .visible else { return }
    phase = .visible
  }

  @discardableResult
  func beginDismiss() -> Bool {
    guard phase == .visible || phase == .appearing else { return false }
    phase = .dismissing
    return true
  }

  func finishHidden() {
    phase = .hidden
    motionProgress = 0
    opacity = 0
    blurRadius = SettingsPresentationMotion.blurredRadius
    scale = SettingsPresentationMotion.compressedScale
  }

  func offset(for piece: SettingsParallaxPiece) -> CGSize {
    let t = 1 - motionProgress
    return CGSize(
      width: piece.enterOffset.width * t,
      height: piece.enterOffset.height * t
    )
  }

  func blur(for piece: SettingsParallaxPiece) -> Double {
    // Blur clears as the piece rises into place.
    piece.enterBlur * (1 - motionProgress)
  }

  func opacity(for piece: SettingsParallaxPiece) -> Double {
    // Fade in alongside the rise; fully clear before travel finishes.
    min(1, max(0, motionProgress / 0.8))
  }
}
