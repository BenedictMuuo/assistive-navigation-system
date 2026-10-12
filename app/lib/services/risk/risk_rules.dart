/// How far away the obstacle is, in three bands.
enum DistanceBand {
  /// Under 1 metre: about one step. Act now.
  near,

  /// 1 to 3 metres: a few steps. Be aware.
  medium,

  /// Over 3 metres: not yet relevant.
  far,

  /// No distance reading: the sensor is disconnected or absent.
  unknown,
}

enum RiskLevel { low, medium, high }

/// Turns raw distance readings into a band, with hysteresis.
///
/// A real ultrasonic sensor wobbles by a few centimetres. Someone standing
/// 1.0 m from a chair would otherwise flip between "near" and "medium"
/// several times a second, and the phone would buzz constantly.
///
/// So moving into a band requires crossing its boundary by [margin]. With
/// the defaults, the band becomes "near" below 0.85 m but only goes back to
/// "medium" above 1.15 m. Anything in between keeps the current band.
class DistanceBander {
  DistanceBander({
    this.nearLimit = 1.0,
    this.farLimit = 3.0,
    this.margin = 0.15,
  }) : assert(nearLimit + margin < farLimit - margin);

  final double nearLimit;
  final double farLimit;
  final double margin;

  DistanceBand _band = DistanceBand.unknown;
  DistanceBand get band => _band;

  DistanceBand update(double? metres) {
    if (metres == null) return _band = DistanceBand.unknown;

    switch (_band) {
      case DistanceBand.unknown:
        // First reading, or reconnection: no history, so no hysteresis.
        _band = _plainBand(metres);
      case DistanceBand.near:
        if (metres > farLimit + margin) {
          _band = DistanceBand.far;
        } else if (metres > nearLimit + margin) {
          _band = DistanceBand.medium;
        }
      case DistanceBand.medium:
        if (metres < nearLimit - margin) {
          _band = DistanceBand.near;
        } else if (metres > farLimit + margin) {
          _band = DistanceBand.far;
        }
      case DistanceBand.far:
        if (metres < nearLimit - margin) {
          _band = DistanceBand.near;
        } else if (metres < farLimit - margin) {
          _band = DistanceBand.medium;
        }
    }
    return _band;
  }

  DistanceBand _plainBand(double metres) {
    if (metres < nearLimit) return DistanceBand.near;
    if (metres <= farLimit) return DistanceBand.medium;
    return DistanceBand.far;
  }

  void reset() => _band = DistanceBand.unknown;
}

/// The risk matrix: what an object at a given distance means for the user.
class RiskTable {
  static const _h = RiskLevel.high;
  static const _m = RiskLevel.medium;
  static const _l = RiskLevel.low;

  /// Columns: near, medium, far.
  ///
  /// Stairs are the most dangerous object the model knows: a fall is
  /// worse than a bump, so they stay high risk even a few steps away.
  /// Chairs, tables, bags and walls are collision hazards that matter only
  /// when close. A bag on the floor is also a trip hazard. People and doors
  /// are lower: people move aside, and a door is usually where the user
  /// means to go.
  static const Map<String, List<RiskLevel>> table = {
    'stairs': [_h, _h, _m],
    'wall': [_h, _m, _l],
    'chair': [_h, _m, _l],
    'table': [_h, _m, _l],
    'bag': [_h, _m, _l],
    'person': [_m, _l, _l],
    'door': [_m, _l, _l],
    'background': [_l, _l, _l],
  };

  static RiskLevel assess(String label, DistanceBand band) {
    if (label == 'background') return RiskLevel.low;

    // No distance: camera-only fallback. Stairs stay high; anything else
    // is treated as medium, because how close it is cannot be known.
    if (band == DistanceBand.unknown) {
      return label == 'stairs' ? RiskLevel.high : RiskLevel.medium;
    }

    final row = table[label];
    // A class missing from the table is treated with caution, not ignored.
    if (row == null) return RiskLevel.medium;
    return row[band.index];
  }
}
