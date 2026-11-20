import AppKit
import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

/// AppKit recorder host — click to record, ✕ to clear, then record again.
struct KeyboardShortcutsRecorderRepresentable: NSViewRepresentable {
  typealias NSViewType = RecorderContainerView

  let name: KeyboardShortcuts.Name
  let onChange: (KeyboardShortcuts.Shortcut?) -> Void

  func makeNSView(context: Context) -> RecorderContainerView {
    RecorderContainerView(name: name, onChange: onChange)
  }

  func updateNSView(_ nsView: RecorderContainerView, context: Context) {
    nsView.recorder.shortcutName = name
  }
}

final class RecorderContainerView: NSView {
  let recorder: KeyboardShortcuts.RecorderCocoa

  init(name: KeyboardShortcuts.Name, onChange: @escaping (KeyboardShortcuts.Shortcut?) -> Void) {
    recorder = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
    super.init(frame: .zero)
    recorder.translatesAutoresizingMaskIntoConstraints = false
    addSubview(recorder)
    setContentHuggingPriority(.defaultHigh, for: .vertical)
    setContentHuggingPriority(.defaultHigh, for: .horizontal)
    setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    NSLayoutConstraint.activate([
      recorder.leadingAnchor.constraint(equalTo: leadingAnchor),
      recorder.trailingAnchor.constraint(equalTo: trailingAnchor),
      recorder.topAnchor.constraint(equalTo: topAnchor),
      recorder.bottomAnchor.constraint(equalTo: bottomAnchor),
      recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
      heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: max(130, recorder.intrinsicContentSize.width), height: 24)
  }
}
#endif
