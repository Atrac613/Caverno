import SwiftUI
import WidgetKit

struct GlanceEntry: TimelineEntry {
  let date: Date
  let glance: WatchGlance
}

struct GlanceProvider: TimelineProvider {
  func placeholder(in context: Context) -> GlanceEntry {
    GlanceEntry(date: Date(), glance: .idle)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (GlanceEntry) -> Void
  ) {
    completion(GlanceEntry(date: Date(), glance: WatchGlanceStore.load()))
  }

  /// A single entry with no refresh date: the watch app pushes a reload when
  /// the state actually changes, so a polling timeline would only spend budget
  /// re-rendering what is already on screen.
  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<GlanceEntry>) -> Void
  ) {
    let entry = GlanceEntry(date: Date(), glance: WatchGlanceStore.load())
    completion(Timeline(entries: [entry], policy: .never))
  }
}

struct CavernoWatchWidgetView: View {
  var entry: GlanceEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label("Caverno", systemImage: symbol)
        .font(.caption2)
        .foregroundStyle(entry.glance.needsAttention ? .orange : .secondary)
      Text(headline)
        .font(.headline)
        .minimumScaleFactor(0.7)
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }

  private var symbol: String {
    if entry.glance.needsAttention { return "exclamationmark.triangle.fill" }
    return entry.glance.busyThreadCount > 0 ? "circle.dotted" : "circle"
  }

  private var headline: String {
    if entry.glance.needsAttention { return "Needs you" }
    switch entry.glance.busyThreadCount {
    case 0: return "Idle"
    case 1: return "1 running"
    default: return "\(entry.glance.busyThreadCount) running"
    }
  }
}

@main
struct CavernoWatchWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: WatchGlanceStore.widgetKind,
      provider: GlanceProvider()
    ) { entry in
      CavernoWatchWidgetView(entry: entry)
    }
    .configurationDisplayName("Caverno")
    .description("Whether a turn is running or waiting on you.")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
