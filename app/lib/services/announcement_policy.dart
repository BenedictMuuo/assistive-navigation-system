/// What the speech layer should do with the latest steady label.
enum AnnounceAction {
  /// Say nothing.
  none,

  /// Speak, nothing else is playing.
  speak,

  /// Cut off whatever is playing and speak this instead.
  interrupt,
}

class Announcement {
  const Announcement(this.action, [this.phrase]);

  static const Announcement silent = Announcement(AnnounceAction.none);

  final AnnounceAction action;
  final String? phrase;
}

/// Decides when to speak, and when to stay quiet.
///
/// Visually impaired pedestrians navigate largely by ear: traffic,
/// footsteps, echoes off walls. An app that talks constantly takes that
/// sense away, and users switch it off. So the rules are:
///
/// - A clear path is silent. Silence is the normal state.
/// - An ordinary obstacle is announced once, when it first becomes steady.
///   It is not repeated while it stays in view.
/// - An urgent obstacle (stairs) is announced immediately, cutting off any
///   speech already playing, and repeated every [urgentRepeat] while it
///   stays in view.
/// - Ordinary announcements never talk over speech already playing. They
///   wait, and are picked up on a later frame.
///
/// This class holds no audio code, so every rule can be unit tested.
class AnnouncementPolicy {
  AnnouncementPolicy({
    this.urgentLabels = const {'stairs'},
    this.urgentRepeat = const Duration(seconds: 5),
    this.clearLabel = 'background',
  });

  final Set<String> urgentLabels;
  final Duration urgentRepeat;
  final String clearLabel;

  String? _lastAnnounced;
  DateTime? _lastAnnouncedAt;

  /// Call once per frame with the smoother's output.
  ///
  /// [steadyLabel] is null while the model is unsure. [speaking] is whether
  /// the speech engine is currently talking.
  Announcement next(
    String? steadyLabel,
    DateTime now, {
    required bool speaking,
  }) {
    // Unsure: say nothing, and keep memory, so a brief wobble in the model
    // does not cause the same obstacle to be announced twice.
    if (steadyLabel == null) return Announcement.silent;

    // Clear path: say nothing, but forget the last obstacle, so that if it
    // comes back into view it is announced again.
    if (steadyLabel == clearLabel) {
      _lastAnnounced = null;
      _lastAnnouncedAt = null;
      return Announcement.silent;
    }

    final bool urgent = urgentLabels.contains(steadyLabel);
    final bool sameAsLast = steadyLabel == _lastAnnounced;

    if (sameAsLast) {
      if (!urgent) return Announcement.silent;
      final last = _lastAnnouncedAt;
      if (last != null && now.difference(last) < urgentRepeat) {
        return Announcement.silent;
      }
    }

    if (speaking && !urgent) return Announcement.silent;

    _lastAnnounced = steadyLabel;
    _lastAnnouncedAt = now;

    return Announcement(
      urgent && speaking ? AnnounceAction.interrupt : AnnounceAction.speak,
      phraseFor(steadyLabel),
    );
  }

  void reset() {
    _lastAnnounced = null;
    _lastAnnouncedAt = null;
  }

  /// Short on purpose. "Chair ahead" is faster to say and to understand
  /// than "A chair has been detected in front of you."
  static String phraseFor(String label) {
    if (label == 'stairs') return 'Stairs ahead. Caution.';
    if (label.isEmpty) return label;
    return '${label[0].toUpperCase()}${label.substring(1)} ahead';
  }
}
