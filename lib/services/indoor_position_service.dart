import 'dart:math';

/// Maps real-world GPS coordinates to a normalized position (0.0 - 1.0)
/// on the Bird Library floor plan image.
///
/// Uses 8 reference points (4 corners + 4 midpoints) for accurate
/// bilinear interpolation.
class IndoorPositionService {
  // ── 4 corners of Bird Library (with ~2-3m buffer) ──
  static const double nwLat = 43.040224, nwLng = -76.133012;
  static const double neLat = 43.040216, neLng = -76.132194;
  static const double seLat = 43.039624, seLng = -76.132204;
  static const double swLat = 43.039633, swLng = -76.133008;

  // ── 4 midpoints for better accuracy ──
  static const double nLat = 43.040229, nLng = -76.132608;
  static const double sLat = 43.039607, sLng = -76.132610;
  static const double eLat = 43.039912, eLng = -76.132206;
  static const double wLat = 43.039924, wLng = -76.133022;

  // ── Rough center ──
  static const double centerLat = 43.039917;
  static const double centerLng = -76.132606;

  /// Returns (x, y) where x and y are 0.0 to 1.0
  /// representing position on the floor map image.
  /// x: 0.0 = left (west), 1.0 = right (east)
  /// y: 0.0 = top (north), 1.0 = bottom (south)
  ///
  /// Returns null if the position is outside the building bounds.
  static ({double x, double y})? getFloorPosition(double lat, double lng) {
    // Calculate position using inverse bilinear interpolation
    // We use the 4 corners to define a quadrilateral and find
    // where the GPS point falls within it as (u, v) in [0,1]

    // Simple approach: use linear interpolation between edges
    // For x (west-east): interpolate longitude between west and east edges
    // For y (north-south): interpolate latitude between north and south edges

    // Calculate the west and east boundaries at this latitude
    final latRatio = _inverseLerp(nwLat, swLat, lat); // 0=north, 1=south

    // West boundary longitude at this latitude
    final westLng = _lerp(nwLng, swLng, latRatio);
    // East boundary longitude at this latitude
    final eastLng = _lerp(neLng, seLng, latRatio);

    // Calculate x position (0=west/left, 1=east/right)
    final x = _inverseLerp(westLng, eastLng, lng);

    // Calculate the north and south boundaries at this longitude
    final lngRatio = _inverseLerp(nwLng, neLng, lng); // 0=west, 1=east

    // North boundary latitude at this longitude
    final northLat = _lerp(nwLat, neLat, lngRatio);
    // South boundary latitude at this longitude
    final southLat = _lerp(swLat, seLat, lngRatio);

    // Calculate y position (0=north/top, 1=south/bottom)
    final y = _inverseLerp(northLat, southLat, lat);

    // Clamp to [0, 1] with small buffer for GPS drift
    final clampedX = x.clamp(0.0, 1.0);
    final clampedY = y.clamp(0.0, 1.0);

    // Check if reasonably inside the building (with 20% buffer for GPS drift)
    if (x < -0.2 || x > 1.2 || y < -0.2 || y > 1.2) {
      return null; // Too far outside
    }

    return (x: clampedX, y: clampedY);
  }

  /// Check if a GPS position is inside or near Bird Library
  static bool isInsideBuilding(
    double lat,
    double lng, {
    double bufferMeters = 30,
  }) {
    final pos = getFloorPosition(lat, lng);
    if (pos == null) return false;

    // With buffer: allow some margin outside 0-1 range
    final buffer = bufferMeters / 70; // rough meters to ratio conversion
    return pos.x >= -buffer &&
        pos.x <= 1 + buffer &&
        pos.y >= -buffer &&
        pos.y <= 1 + buffer;
  }

  /// Get distance from building center in meters
  static double distanceFromCenter(double lat, double lng) {
    return _haversineDistance(lat, lng, centerLat, centerLng);
  }

  // ── Math helpers ──

  static double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }

  static double _inverseLerp(double a, double b, double value) {
    if ((b - a).abs() < 1e-10) return 0.5;
    return (value - a) / (b - a);
  }

  static double _haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
}
