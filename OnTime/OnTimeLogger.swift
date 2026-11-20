import Foundation

struct OnTimeLogEvent: Encodable {
  let event: String
  let ts: TimeInterval
  let fields: [String: String]

  enum CodingKeys: String, CodingKey {
    case event, ts
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: DynamicKey.self)
    try container.encode(event, forKey: DynamicKey(stringValue: "event")!)
    try container.encode(ts, forKey: DynamicKey(stringValue: "ts")!)
    for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
      try container.encode(value, forKey: DynamicKey(stringValue: key)!)
    }
  }

  private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }
}

final class OnTimeLogger {
  static let shared = OnTimeLogger()

  private let fileURL: URL
  var logFileURL: URL { fileURL }
  private let queue = DispatchQueue(label: "com.ramiruwanigathunga.ontime.logger")
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  init(fileManager: FileManager = .default, fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
      let dir = fileURL.deletingLastPathComponent()
      try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    } else {
      let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      let dir = support.appendingPathComponent("OnTime", isDirectory: true)
      try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
      self.fileURL = dir.appendingPathComponent("sessions.jsonl")
    }
    if !fileManager.fileExists(atPath: self.fileURL.path) {
      fileManager.createFile(atPath: self.fileURL.path, contents: nil)
    }
  }

  func log(event: String, fields: [String: String] = [:], at date: Date = Date()) {
    let payload = OnTimeLogEvent(event: event, ts: date.timeIntervalSince1970, fields: fields)
    queue.async {
      guard let data = try? self.encoder.encode(payload),
        var line = String(data: data, encoding: .utf8)
      else { return }
      line.append("\n")
      guard let handle = try? FileHandle(forWritingTo: self.fileURL) else { return }
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      if let bytes = line.data(using: .utf8) {
        try? handle.write(contentsOf: bytes)
      }
    }
  }

  /// Sum of completed focus/work seconds for the local calendar day.
  func todaysFocusSeconds(now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
    guard let data = try? Data(contentsOf: fileURL),
      let text = String(data: data, encoding: .utf8)
    else { return 0 }

    let startOfDay = calendar.startOfDay(for: now)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
    let startTs = startOfDay.timeIntervalSince1970
    let endTs = endOfDay.timeIntervalSince1970

    var total: TimeInterval = 0
    for line in text.split(whereSeparator: \.isNewline) {
      guard let lineData = line.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let event = obj["event"] as? String,
        let ts = obj["ts"] as? Double,
        ts >= startTs, ts < endTs
      else { continue }

      if let focus = Self.number(obj["focus_seconds"]) {
        total += focus
        continue
      }

      if event == "timer_complete",
        (obj["mode"] as? String) != "stopwatch",
        let duration = Self.number(obj["duration"])
      {
        total += duration
      } else if event == "phase_transition",
        let from = obj["from"] as? String,
        from.lowercased().contains("work"),
        let duration = Self.number(obj["duration"])
      {
        total += duration
      }
    }
    return total
  }

  func todaysFocusSummary(now: Date = Date()) -> String {
    let seconds = Int(todaysFocusSeconds(now: now).rounded())
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 {
      return "Today’s Focus · \(hours)h \(minutes)m"
    }
    return "Today’s Focus · \(minutes)m"
  }

  private static func number(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let s = value as? String { return Double(s) }
    return nil
  }
}
