import 'dart:convert';
import 'package:flutter/services.dart';

class LibrarySearchResult {
  final String name;
  final String? roomNumber;
  final String floorId;
  final String floorLabel;
  final int floorIndex;
  final String type;
  final String compassDirection;
  final String? description;
  final bool isStudyRoom;
  final bool isTeamRoom;

  LibrarySearchResult({
    required this.name,
    this.roomNumber,
    required this.floorId,
    required this.floorLabel,
    required this.floorIndex,
    required this.type,
    required this.compassDirection,
    this.description,
    this.isStudyRoom = false,
    this.isTeamRoom = false,
  });

  String get directionLabel {
    const labels = {
      'north': 'North',
      'northeast': 'Northeast',
      'east': 'East',
      'southeast': 'Southeast',
      'south': 'South',
      'southwest': 'Southwest',
      'west': 'West',
      'northwest': 'Northwest',
    };
    return labels[compassDirection] ?? compassDirection;
  }

  String get shortDirection {
    const labels = {
      'north': 'N',
      'northeast': 'NE',
      'east': 'E',
      'southeast': 'SE',
      'south': 'S',
      'southwest': 'SW',
      'west': 'W',
      'northwest': 'NW',
    };
    return labels[compassDirection] ?? compassDirection;
  }

  String get typeLabel {
    const labels = {
      'study_room': 'Study Room',
      'open_study': 'Open Study Area',
      'quiet_space': 'Quiet Space',
      'book_stacks': 'Book Stacks',
      'service_desk': 'Service Desk',
      'dining': 'Dining & Café',
      'technology': 'Technology',
      'office': 'Office',
      'classroom': 'Classroom',
      'student_success': 'Student Success',
      'faculty_success': 'Faculty',
      'special_collection': 'Special Collection',
      'exhibition': 'Exhibition',
      'meeting_room': 'Meeting Room',
      'learning_commons': 'Learning Commons',
      'scholarly_commons': 'Scholarly Commons',
      'staff_area': 'Staff Area',
      'room': 'Room',
      'amenity_printer': 'Printer',
      'amenity_restroom': 'Restroom',
      'amenity_water': 'Water Fountain',
      'amenity_elevator': 'Elevator',
      'amenity_quiet': 'Quiet Space',
      'amenity_dining': 'Dining',
    };
    return labels[type] ?? type;
  }
}

class LibrarySearchService {
  Map<String, dynamic>? _data;
  List<LibrarySearchResult> _allResults = [];
  bool _isLoaded = false;

  static const List<String> floorIds = ['B', '1', '2', '3', '4', '5', '6'];
  static const List<String> floorLabels = [
    'Lower Level (B)',
    'First Floor (1)',
    'Second Floor (2)',
    'Third Floor (3)',
    'Fourth Floor (4)',
    'Fifth Floor (5)',
    'Sixth Floor (6)',
  ];

  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final jsonString = await rootBundle.loadString(
        'assets/data/bird_library_indoor.json',
      );
      _data = json.decode(jsonString) as Map<String, dynamic>;
      _buildSearchIndex();
      _isLoaded = true;
    } catch (e) {
      // ignore - will just return empty results
    }
  }

  void _buildSearchIndex() {
    _allResults.clear();
    final floors = _data?['floors'] as List<dynamic>? ?? [];

    for (final floor in floors) {
      final floorId = floor['floorId'] as String;
      final floorLabel = floor['floorLabel'] as String;
      final floorIndex = floorIds.indexOf(floorId);

      // Index zones
      final zones = floor['zones'] as List<dynamic>? ?? [];
      for (final zone in zones) {
        _allResults.add(
          LibrarySearchResult(
            name: zone['name'] as String,
            roomNumber: zone['roomNumber'] as String?,
            floorId: floorId,
            floorLabel: floorLabel,
            floorIndex: floorIndex,
            type: zone['type'] as String,
            compassDirection: zone['compassDirection'] as String? ?? 'north',
            description: zone['description'] as String?,
          ),
        );
      }

      // Index study rooms
      final studyRooms = floor['studyRooms'] as List<dynamic>? ?? [];
      for (final room in studyRooms) {
        final roomNum = room['roomNumber'] as String;
        final isTeam = room['isTeamRoom'] == true;

        // Determine compass direction based on room number pattern
        String direction = _estimateStudyRoomDirection(roomNum, floorId);

        _allResults.add(
          LibrarySearchResult(
            name: isTeam ? 'Team Room $roomNum' : 'Study Room $roomNum',
            roomNumber: roomNum,
            floorId: floorId,
            floorLabel: floorLabel,
            floorIndex: floorIndex,
            type: 'study_room',
            compassDirection: direction,
            description:
                isTeam
                    ? 'Team/group study room on $floorLabel'
                    : 'Individual study room on $floorLabel',
            isStudyRoom: true,
            isTeamRoom: isTeam,
          ),
        );
      }
    }

    // Index amenities from amenitySearch
    _indexAmenities();
  }

  void _indexAmenities() {
    final amenitySearch =
        _data?['amenitySearch'] as Map<String, dynamic>? ?? {};

    // Printers
    final printers = amenitySearch['printers'] as List<dynamic>? ?? [];
    for (final p in printers) {
      final floorId = p['floor'] as String;
      final floorIndex = floorIds.indexOf(floorId);
      _allResults.add(
        LibrarySearchResult(
          name: 'Printer - ${p['location']}',
          floorId: floorId,
          floorLabel: floorLabels[floorIndex],
          floorIndex: floorIndex,
          type: 'amenity_printer',
          compassDirection: p['compassDirection'] as String? ?? 'east',
          description: 'Print, copy, and scan station',
        ),
      );
    }

    // Restrooms
    final restrooms = amenitySearch['restrooms'] as List<dynamic>? ?? [];
    for (final r in restrooms) {
      final floorId = r['floor'] as String;
      final floorIndex = floorIds.indexOf(floorId);
      final types = r['types'] ?? [r['type'] ?? 'restroom'];
      final typeStr = types is List ? types.join(', ') : types.toString();
      _allResults.add(
        LibrarySearchResult(
          name: 'Restroom ($typeStr)',
          floorId: floorId,
          floorLabel: floorLabels[floorIndex],
          floorIndex: floorIndex,
          type: 'amenity_restroom',
          compassDirection: r['compassDirection'] as String? ?? 'east',
          description: 'Restroom on ${floorLabels[floorIndex]}',
        ),
      );
    }

    // Water fountains
    final water = amenitySearch['waterFountains'] as List<dynamic>? ?? [];
    for (final w in water) {
      final floorId = w['floor'] as String;
      final floorIndex = floorIds.indexOf(floorId);
      _allResults.add(
        LibrarySearchResult(
          name: 'Water Fountain',
          floorId: floorId,
          floorLabel: floorLabels[floorIndex],
          floorIndex: floorIndex,
          type: 'amenity_water',
          compassDirection: w['compassDirection'] as String? ?? 'east',
          description: 'Water fountain on ${floorLabels[floorIndex]}',
        ),
      );
    }

    // Quiet spaces
    final quiet = amenitySearch['quietSpaces'] as List<dynamic>? ?? [];
    for (final q in quiet) {
      final floorId = q['floor'] as String;
      final floorIndex = floorIds.indexOf(floorId);
      _allResults.add(
        LibrarySearchResult(
          name: q['name'] as String,
          roomNumber: q['roomNumber'] as String?,
          floorId: floorId,
          floorLabel: floorLabels[floorIndex],
          floorIndex: floorIndex,
          type: 'amenity_quiet',
          compassDirection: 'east',
          description: 'Quiet study space',
        ),
      );
    }

    // Dining
    final dining = amenitySearch['dining'] as List<dynamic>? ?? [];
    for (final d in dining) {
      final floorId = d['floor'] as String;
      final floorIndex = floorIds.indexOf(floorId);
      _allResults.add(
        LibrarySearchResult(
          name: d['name'] as String,
          roomNumber: d['roomNumber'] as String?,
          floorId: floorId,
          floorLabel: floorLabels[floorIndex],
          floorIndex: floorIndex,
          type: 'amenity_dining',
          compassDirection: d['compassDirection'] as String? ?? 'east',
          description: 'Dining and refreshments',
        ),
      );
    }
  }

  /// Estimate study room direction based on room number patterns
  /// from the floor maps (rooms along perimeter in predictable order)
  String _estimateStudyRoomDirection(String roomNum, String floorId) {
    // Extract the numeric part
    final numStr = roomNum.replaceAll(RegExp(r'[^0-9]'), '');
    if (numStr.isEmpty) return 'north';
    final num = int.tryParse(numStr) ?? 0;
    final lastTwo = num % 100;

    // Rooms on floors 3-5 follow a consistent perimeter pattern:
    // 00-06: top-right (northeast)
    // 08-13: right side (east/southeast)
    // 15-18: bottom-right (southeast)
    // 20-25: bottom (south)
    // 26-31: bottom-left (southwest)
    // 34-36: left side (west)
    // 38-44: top-left (northwest/north)
    // 51-56: center-right (east)

    if (lastTwo >= 0 && lastTwo <= 6) return 'northeast';
    if (lastTwo >= 8 && lastTwo <= 13) return 'east';
    if (lastTwo >= 15 && lastTwo <= 18) return 'southeast';
    if (lastTwo >= 20 && lastTwo <= 25) return 'south';
    if (lastTwo >= 26 && lastTwo <= 31) return 'southwest';
    if (lastTwo >= 32 && lastTwo <= 36) return 'west';
    if (lastTwo >= 38 && lastTwo <= 46) return 'northwest';
    if (lastTwo >= 48 && lastTwo <= 56) return 'east';
    return 'north';
  }

  /// Search for rooms, zones, or amenities
  List<LibrarySearchResult> search(String query) {
    if (!_isLoaded || query.trim().isEmpty) return [];

    final q = query.trim().toLowerCase();
    final results = <LibrarySearchResult>[];

    for (final item in _allResults) {
      bool matches = false;

      // Match by room number (exact or starts-with)
      if (item.roomNumber != null) {
        final rn = item.roomNumber!.toLowerCase();
        if (rn == q || rn.startsWith(q)) {
          matches = true;
        }
      }

      // Match by name
      if (!matches && item.name.toLowerCase().contains(q)) {
        matches = true;
      }

      // Match by type keywords
      if (!matches) {
        if (q.contains('print') && item.type == 'amenity_printer') {
          matches = true;
        }
        if (q.contains('restroom') ||
            q.contains('bathroom') ||
            q.contains('toilet')) {
          if (item.type == 'amenity_restroom') matches = true;
        }
        if (q.contains('water') || q.contains('fountain')) {
          if (item.type == 'amenity_water') matches = true;
        }
        if (q.contains('quiet') || q.contains('silent')) {
          if (item.type == 'amenity_quiet' || item.type == 'quiet_space') {
            matches = true;
          }
        }
        if (q.contains('cafe') || q.contains('coffee') || q.contains('food')) {
          if (item.type == 'amenity_dining' || item.type == 'dining') {
            matches = true;
          }
        }
        if (q.contains('study') && item.type == 'study_room') {
          matches = true;
        }
        if (q.contains('team') && item.isTeamRoom) {
          matches = true;
        }
        if (q.contains('elevator') || q.contains('lift')) {
          if (item.type == 'amenity_elevator') matches = true;
        }
      }

      // Match by description
      if (!matches && item.description != null) {
        if (item.description!.toLowerCase().contains(q)) {
          matches = true;
        }
      }

      if (matches) results.add(item);
    }

    // Sort: exact room number matches first, then by floor
    results.sort((a, b) {
      // Exact room number match gets priority
      final aExact = a.roomNumber?.toLowerCase() == q ? 0 : 1;
      final bExact = b.roomNumber?.toLowerCase() == q ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);

      // Then by floor
      return a.floorIndex.compareTo(b.floorIndex);
    });

    return results;
  }

  /// Find nearest amenity of a type from a given floor
  List<LibrarySearchResult> findNearestAmenity(
    String amenityType,
    int currentFloorIndex,
  ) {
    final results = _allResults.where((r) => r.type == amenityType).toList();

    // Sort by distance from current floor
    results.sort((a, b) {
      final aDist = (a.floorIndex - currentFloorIndex).abs();
      final bDist = (b.floorIndex - currentFloorIndex).abs();
      return aDist.compareTo(bDist);
    });

    return results;
  }
}
