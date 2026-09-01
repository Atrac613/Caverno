import Foundation

/// The little the Smart Stack needs to know, shared between the watch app and
/// its widget.
///
/// Deliberately not the snapshot. A widget shows a glance, and anything richer
/// would put conversation text into a surface that renders without the user
/// opening anything. Counts and a status word carry no content.
struct WatchGlance: Codable, Equatable {
  let status: String
  let busyThreadCount: Int
  let needsAttention: Bool
  let updatedAt: Date

  static let idle = WatchGlance(
    status: "idle",
    busyThreadCount: 0,
    needsAttention: false,
    updatedAt: Date(timeIntervalSince1970: 0)
  )
}

/// Reads and writes [WatchGlance] through the shared App Group.
///
/// App Group containers are per-device, which is exactly right here: the watch
/// app and its widget run on the same watch. Nothing crosses to the phone this
/// way — that is what WatchConnectivity is for.
enum WatchGlanceStore {
  static let appGroupId = "group.com.noguwo.apps.caverno"
  static let widgetKind = "CavernoWatchGlance"
  private static let key = "watch_glance"

  static func load() -> WatchGlance {
    guard
      let defaults = UserDefaults(suiteName: appGroupId),
      let data = defaults.data(forKey: key),
      let glance = try? JSONDecoder().decode(WatchGlance.self, from: data)
    else {
      return .idle
    }
    return glance
  }

  /// Returns true when the stored value actually changed, so the caller can
  /// avoid asking WidgetKit to reload a timeline that would render the same.
  @discardableResult
  static func save(_ glance: WatchGlance) -> Bool {
    guard let defaults = UserDefaults(suiteName: appGroupId) else {
      return false
    }
    let previous = load()
    guard
      previous.status != glance.status
        || previous.busyThreadCount != glance.busyThreadCount
        || previous.needsAttention != glance.needsAttention
    else {
      return false
    }
    guard let data = try? JSONEncoder().encode(glance) else { return false }
    defaults.set(data, forKey: key)
    return true
  }
}
