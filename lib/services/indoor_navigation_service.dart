import 'dart:math';

/// Multi-floor navigation inside Bird Library.
///
/// Transit points (GPS from user measurements):
///   - Public Elevator: 43.039806, -76.132500 — ALL floors (B-6)
///   - South Stairs:    43.039861, -76.132806 — Basement ↔ Floor 1 ↔ Floor 2
///   - North Stairs:    43.040028, -76.132611 — Floor 2 ↔ Floor 3 ↔ Floor 4 ↔ Floor 5
///
/// Floor 6 is elevator-only.
/// If user picks stairs for a route that spans both stairways (e.g. Floor 1→5),
/// the app creates a multi-leg route:
///   Leg 1: South Stairs from Floor 1 → Floor 2
///   Leg 2: Walk to North Stairs on Floor 2
///   Leg 3: North Stairs from Floor 2 → Floor 5
class IndoorNavigationService {
  // ── Exact GPS coordinates ──
  static const double elevatorLat = 43.039806;
  static const double elevatorLng = -76.132472;
  static const double southStairsLat = 43.039778;
  static const double southStairsLng = -76.132750;
  static const double northStairsLat = 43.040056;
  static const double northStairsLng = -76.132528;

  // ── Detection radius ──
  static const double arrivalRadius = 8.0; // meters

  // ── Floor index: B=0, 1=1, 2=2, 3=3, 4=4, 5=5, 6=6 ──

  /// South stairs serve floors B(0), 1(1), 2(2)
  static const Set<int> southStairsFloors = {0, 1, 2};

  /// North stairs serve floors 2(2), 3(3), 4(4), 5(5)
  static const Set<int> northStairsFloors = {2, 3, 4, 5};

  /// Check what transit options are available for a route
  static List<TransitOption> getTransitOptions(int fromFloor, int toFloor) {
    final options = <TransitOption>[];

    // Elevator always works
    options.add(
      TransitOption(
        type: TransitChoice.elevator,
        label: 'Elevator',
        icon: 'elevator',
        subtitle: 'Direct — all floors',
        legs: [
          NavLeg(
            transitType: TransitType.elevator,
            targetLat: elevatorLat,
            targetLng: elevatorLng,
            fromFloor: fromFloor,
            toFloor: toFloor,
            label: 'Elevator',
          ),
        ],
      ),
    );

    // Floor 6 = elevator only
    if (fromFloor == 6 || toFloor == 6) {
      return options;
    }

    // Check if a single stairway can do the trip
    if (southStairsFloors.contains(fromFloor) &&
        southStairsFloors.contains(toFloor)) {
      options.add(
        TransitOption(
          type: TransitChoice.stairs,
          label: 'South Stairs',
          icon: 'stairs',
          subtitle: 'Basement – Floor 2',
          legs: [
            NavLeg(
              transitType: TransitType.southStairs,
              targetLat: southStairsLat,
              targetLng: southStairsLng,
              fromFloor: fromFloor,
              toFloor: toFloor,
              label: 'South Stairs',
            ),
          ],
        ),
      );
    }

    if (northStairsFloors.contains(fromFloor) &&
        northStairsFloors.contains(toFloor)) {
      options.add(
        TransitOption(
          type: TransitChoice.stairs,
          label: 'North Stairs',
          icon: 'stairs',
          subtitle: 'Floor 2 – Floor 5',
          legs: [
            NavLeg(
              transitType: TransitType.northStairs,
              targetLat: northStairsLat,
              targetLng: northStairsLng,
              fromFloor: fromFloor,
              toFloor: toFloor,
              label: 'North Stairs',
            ),
          ],
        ),
      );
    }

    // Multi-leg stair route: needs both stairways via Floor 2
    // e.g. Floor B/1 → Floor 3/4/5 or vice versa
    final needsMultiLeg =
        !southStairsFloors.contains(toFloor) &&
        southStairsFloors.contains(fromFloor) &&
        northStairsFloors.contains(toFloor);
    final needsMultiLegReverse =
        !southStairsFloors.contains(fromFloor) &&
        northStairsFloors.contains(fromFloor) &&
        southStairsFloors.contains(toFloor);

    if (needsMultiLeg) {
      // Going UP: e.g. Floor 1 → Floor 5
      // Leg 1: South Stairs to Floor 2
      // Leg 2: Walk to North Stairs on Floor 2
      // Leg 3: North Stairs to target
      options.add(
        TransitOption(
          type: TransitChoice.stairs,
          label: 'Stairs (via Floor 2)',
          icon: 'stairs',
          subtitle: 'South Stairs → Floor 2 → North Stairs',
          legs: [
            NavLeg(
              transitType: TransitType.southStairs,
              targetLat: southStairsLat,
              targetLng: southStairsLng,
              fromFloor: fromFloor,
              toFloor: 2,
              label: 'South Stairs',
            ),
            NavLeg(
              transitType: TransitType.walkToTransfer,
              targetLat: northStairsLat,
              targetLng: northStairsLng,
              fromFloor: 2,
              toFloor: 2,
              label: 'Walk to North Stairs',
            ),
            NavLeg(
              transitType: TransitType.northStairs,
              targetLat: northStairsLat,
              targetLng: northStairsLng,
              fromFloor: 2,
              toFloor: toFloor,
              label: 'North Stairs',
            ),
          ],
        ),
      );
    }

    if (needsMultiLegReverse) {
      // Going DOWN: e.g. Floor 5 → Floor 1
      // Leg 1: North Stairs to Floor 2
      // Leg 2: Walk to South Stairs on Floor 2
      // Leg 3: South Stairs to target
      options.add(
        TransitOption(
          type: TransitChoice.stairs,
          label: 'Stairs (via Floor 2)',
          icon: 'stairs',
          subtitle: 'North Stairs → Floor 2 → South Stairs',
          legs: [
            NavLeg(
              transitType: TransitType.northStairs,
              targetLat: northStairsLat,
              targetLng: northStairsLng,
              fromFloor: fromFloor,
              toFloor: 2,
              label: 'North Stairs',
            ),
            NavLeg(
              transitType: TransitType.walkToTransfer,
              targetLat: southStairsLat,
              targetLng: southStairsLng,
              fromFloor: 2,
              toFloor: 2,
              label: 'Walk to South Stairs',
            ),
            NavLeg(
              transitType: TransitType.southStairs,
              targetLat: southStairsLat,
              targetLng: southStairsLng,
              fromFloor: 2,
              toFloor: toFloor,
              label: 'South Stairs',
            ),
          ],
        ),
      );
    }

    return options;
  }

  /// Calculate bearing from user to target
  static double bearingTo(
    double userLat,
    double userLng,
    double targetLat,
    double targetLng,
  ) {
    final dLon = (targetLng - userLng) * pi / 180;
    final lat1 = userLat * pi / 180;
    final lat2 = targetLat * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// Get instruction for the current leg of navigation
  static NavigationInstruction getLegInstruction({
    required double userLat,
    required double userLng,
    required NavLeg leg,
    required int currentFloorIndex,
    required String finalRoomName,
    required String finalDirection,
    required String finalFloorLabel,
    required bool isLastLeg,
  }) {
    final distToTarget = _distance(
      userLat,
      userLng,
      leg.targetLat,
      leg.targetLng,
    );
    final isNear = distToTarget <= arrivalRadius;

    // If this is a "walk to transfer" leg (walking between stairs on same floor)
    if (leg.transitType == TransitType.walkToTransfer) {
      if (isNear) {
        return NavigationInstruction(
          phase: NavPhase.atTransit,
          message: 'You\'re at the ${leg.label.replaceAll('Walk to ', '')}',
          detail: 'Now take them to reach your destination',
          targetLat: null,
          targetLng: null,
          showArrow: false,
          transitType: leg.transitType,
          isAtTransitReady: true,
        );
      } else {
        return NavigationInstruction(
          phase: NavPhase.walkingToTransit,
          message: '${leg.label} (${distToTarget.toInt()}m)',
          detail: 'On Floor 2 — transfer between stairways',
          targetLat: leg.targetLat,
          targetLng: leg.targetLng,
          showArrow: true,
          transitType: leg.transitType,
        );
      }
    }

    // Regular stairs/elevator leg
    if (leg.fromFloor != currentFloorIndex) {
      // Not on the right floor for this leg yet
      return NavigationInstruction(
        phase: NavPhase.atTransit,
        message: 'Switch to floor for next step',
        detail: null,
        targetLat: null,
        targetLng: null,
        showArrow: false,
        transitType: leg.transitType,
      );
    }

    if (isNear) {
      final floorDiff = leg.toFloor - leg.fromFloor;
      final floorWord = floorDiff > 0 ? 'up' : 'down';
      final floorCount = floorDiff.abs();

      String nextHint;
      if (isLastLeg) {
        nextHint = 'Then face $finalDirection for $finalRoomName';
      } else {
        nextHint = 'Continue to next step after';
      }

      return NavigationInstruction(
        phase: NavPhase.atTransit,
        message:
            'Take ${leg.label.toLowerCase()} $floorCount floor${floorCount > 1 ? 's' : ''} $floorWord',
        detail: nextHint,
        targetLat: null,
        targetLng: null,
        showArrow: false,
        transitType: leg.transitType,
        isAtTransitReady: true,
        switchToFloor: leg.toFloor,
      );
    } else {
      return NavigationInstruction(
        phase: NavPhase.walkingToTransit,
        message: 'Head to ${leg.label} (${distToTarget.toInt()}m)',
        detail:
            isLastLeg
                ? 'Then go to $finalFloorLabel'
                : 'Step ${leg.fromFloor == currentFloorIndex ? "in progress" : "upcoming"}',
        targetLat: leg.targetLat,
        targetLng: leg.targetLng,
        showArrow: true,
        transitType: leg.transitType,
      );
    }
  }

  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

// ── Enums & Models ──

enum TransitType { elevator, southStairs, northStairs, walkToTransfer }

enum TransitChoice { elevator, stairs }

enum NavPhase { walkingToTransit, atTransit, onTargetFloor }

class TransitOption {
  final TransitChoice type;
  final String label;
  final String icon;
  final String subtitle;
  final List<NavLeg> legs;

  TransitOption({
    required this.type,
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.legs,
  });
}

class NavLeg {
  final TransitType transitType;
  final double targetLat;
  final double targetLng;
  final int fromFloor;
  final int toFloor;
  final String label;

  NavLeg({
    required this.transitType,
    required this.targetLat,
    required this.targetLng,
    required this.fromFloor,
    required this.toFloor,
    required this.label,
  });
}

class NavigationInstruction {
  final NavPhase phase;
  final String message;
  final String? detail;
  final double? targetLat;
  final double? targetLng;
  final bool showArrow;
  final TransitType? transitType;
  final bool isAtTransitReady;
  final int? switchToFloor;

  NavigationInstruction({
    required this.phase,
    required this.message,
    this.detail,
    this.targetLat,
    this.targetLng,
    required this.showArrow,
    this.transitType,
    this.isAtTransitReady = false,
    this.switchToFloor,
  });
}
