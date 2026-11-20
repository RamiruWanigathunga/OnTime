import AppKit

enum MenuBarRingImage {
  private static var cachedKey: String?
  private static var cachedImage: NSImage?

  static func make(
    progress: Double,
    size: NSSize,
    showBadge: Bool = false,
    badgeText: String? = nil
  ) -> NSImage {
    // Quantize progress so tenths-precision ticks don’t allocate a fresh image every frame.
    let quantized = (min(max(progress, 0), 1) * 200).rounded() / 200
    let key =
      "\(quantized)_\(Int(size.width * 10))x\(Int(size.height * 10))_\(showBadge)_\(badgeText ?? "")"
    if key == cachedKey, let cachedImage {
      return cachedImage
    }

    let image = NSImage(size: size, flipped: false) { rect in
      let inset: CGFloat = 1.5
      let drawRect = rect.insetBy(dx: inset, dy: inset)
      let center = NSPoint(x: drawRect.midX, y: drawRect.midY)
      let radius = min(drawRect.width, drawRect.height) / 2
      let lineWidth = max(1.5, radius * 0.22)

      let track = NSBezierPath(
        ovalIn: NSRect(
          x: center.x - radius,
          y: center.y - radius,
          width: radius * 2,
          height: radius * 2
        )
      )
      track.lineWidth = lineWidth
      NSColor.black.withAlphaComponent(0.25).setStroke()
      track.stroke()

      if quantized > 0.001 {
        let arc = NSBezierPath()
        let startAngle = 90.0
        let endAngle = startAngle - (360.0 * quantized)
        arc.appendArc(
          withCenter: center,
          radius: radius,
          startAngle: startAngle,
          endAngle: endAngle,
          clockwise: true
        )
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor.black.setStroke()
        arc.stroke()
      }

      if showBadge {
        if let badgeText, !badgeText.isEmpty {
          let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
              ofSize: max(7, size.height * 0.32), weight: .bold),
            .foregroundColor: NSColor.black,
          ]
          let drawn = NSAttributedString(string: badgeText, attributes: attrs)
          let textSize = drawn.size()
          let origin = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
          )
          drawn.draw(at: origin)
        } else {
          let badge = NSBezierPath(
            ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 4, height: 4)
          )
          NSColor.black.setFill()
          badge.fill()
        }
      }
      return true
    }
    image.isTemplate = true
    cachedKey = key
    cachedImage = image
    return image
  }
}
