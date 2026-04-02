import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/building.dart';

class BuildingService {
  List<Building>? _cachedBuildings;

  // Load buildings from the local JSON file in assets/
  Future<List<Building>> loadLocalBuildings() async {
    final jsonString = await rootBundle.loadString(
      'assets/data/su_buildings.json',
    );
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList
        .map((j) => Building.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // Get all buildings — uses cache so JSON is only loaded once
  Future<List<Building>> getAllBuildings() async {
    if (_cachedBuildings != null) return _cachedBuildings!;
    _cachedBuildings = await loadLocalBuildings();
    return _cachedBuildings!;
  }

  // Find one building by its ID
  Future<Building?> getBuildingById(String id) async {
    final buildings = await getAllBuildings();
    try {
      return buildings.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  // Search — checks building name, departments, faculty names, rooms
  Future<List<Building>> searchBuildings(String query) async {
    final buildings = await getAllBuildings();
    final q = query.toLowerCase();
    return buildings.where((b) {
      if (b.name.toLowerCase().contains(q)) return true;
      if (b.departments.any((d) => d.toLowerCase().contains(q))) return true;
      if (b.faculty.any((f) => f.name.toLowerCase().contains(q))) return true;
      if (b.rooms.any((r) => (r.name ?? '').toLowerCase().contains(q)))
        return true;
      if ((b.campusRegion ?? '').toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  // Filter by building type
  Future<List<Building>> getBuildingsByType(BuildingType type) async {
    final buildings = await getAllBuildings();
    return buildings.where((b) => b.type == type).toList();
  }

  // Get all faculty across all buildings matching a query
  Future<List<Faculty>> searchFaculty(String query) async {
    final buildings = await getAllBuildings();
    final q = query.toLowerCase();
    final results = <Faculty>[];
    for (final b in buildings) {
      for (final f in b.faculty) {
        if (f.name.toLowerCase().contains(q) ||
            (f.department ?? '').toLowerCase().contains(q)) {
          results.add(f);
        }
      }
    }
    return results;
  }
}
