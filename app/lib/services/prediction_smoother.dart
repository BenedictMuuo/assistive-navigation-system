import 'dart:collection';

/// Steadies the model's output before anything is shown or spoken.
///
/// Frame-by-frame predictions flicker. A camera moving past a chair might
/// read chair, table, chair, wall, chair. Announcing every change would be
/// unusable, so a label is only accepted when it wins [required] of the
/// last [window] frames, each at or above [threshold] confidence.
///
/// With the defaults - 3 of the last 5 at 0.7 - the app stays silent when
/// it is unsure. Staying silent is the safe failure: a user who hears
/// nothing keeps using their cane, but a user told the wrong thing has
/// been actively misled.
class PredictionSmoother {
  PredictionSmoother({
    this.window = 5,
    this.required = 3,
    this.threshold = 0.7,
  })  : assert(required <= window),
        assert(threshold >= 0 && threshold <= 1);

  final int window;
  final int required;
  final double threshold;

  // A null entry means that frame was below the confidence threshold.
  final Queue<String?> _recent = Queue<String?>();

  /// Adds one frame's prediction. Returns the steady label, or null if no
  /// label is steady enough yet.
  String? add(String label, double confidence) {
    _recent.addLast(confidence >= threshold ? label : null);
    while (_recent.length > window) {
      _recent.removeFirst();
    }
    return current;
  }

  /// The steady label right now, or null.
  String? get current {
    final counts = <String, int>{};
    for (final label in _recent) {
      if (label == null) continue;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    for (final entry in counts.entries) {
      if (entry.value >= required) return entry.key;
    }
    return null;
  }

  void reset() => _recent.clear();
}
