import Foundation

/// The day-and-time header Messages puts above a group of bubbles.
///
/// Formatted on the watch rather than on the phone. The frame carries UTC,
/// and only this device knows the locale and the 12/24-hour setting the
/// person actually reads — a phone that formatted the string would have to
/// guess which of the two devices' settings to use.
enum TranscriptTimestamp {
  /// Bubbles closer together than this share one header, so a burst of turns
  /// does not get a timestamp between every line.
  static let groupingInterval: TimeInterval = 15 * 60

  static func label(for date: Date) -> String {
    formatter.string(from: date)
  }

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    // Yields "Yesterday 2:08 PM" / "昨日 2:08" instead of a bare date.
    formatter.doesRelativeDateFormatting = true
    return formatter
  }()
}
