import 'package:equatable/equatable.dart';

// Building types — the app switches UI based on this
enum BuildingType { university, commercial, historical, mixed }

// Main building data model
class Building extends Equatable {
  final String id;
  final String name;
  final BuildingType type;
  final double latitude;
  final double longitude;
  final String? address;
  final String? imageUrl;
  final String? description;
  final int? constructionYear;
  final String? architect;
  final String? architecturalStyle;
  final List<String> notableEvents;
  final List<Faculty> faculty;
  final List<Room> rooms;
  final List<String> departments;
  final String? campusRegion;
  final String? reserveRoomUrl;

  const Building({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    this.imageUrl,
    this.description,
    this.constructionYear,
    this.architect,
    this.architecturalStyle,
    this.notableEvents = const [],
    this.faculty = const [],
    this.rooms = const [],
    this.departments = const [],
    this.campusRegion,
    this.reserveRoomUrl,
  });

  // Convert JSON map into a Building object
  // Used when loading from local JSON file or Firebase
  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'] as String,
      name: json['name'] as String,
      type: BuildingType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => BuildingType.university,
      ),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      imageUrl: json['imageUrl'] as String?,
      description: json['description'] as String?,
      constructionYear: json['constructionYear'] as int?,
      architect: json['architect'] as String?,
      architecturalStyle: json['architecturalStyle'] as String?,
      notableEvents: List<String>.from(json['notableEvents'] ?? []),
      faculty:
          (json['faculty'] as List<dynamic>?)
              ?.map((f) => Faculty.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      rooms:
          (json['rooms'] as List<dynamic>?)
              ?.map((r) => Room.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      departments: List<String>.from(json['departments'] ?? []),
      campusRegion: json['campusRegion'] as String?,
      reserveRoomUrl: json['reserveRoomUrl'] as String?,
    );
  }

  // Convert Building back to JSON (for saving to Firebase)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'imageUrl': imageUrl,
      'description': description,
      'constructionYear': constructionYear,
      'architect': architect,
      'architecturalStyle': architecturalStyle,
      'notableEvents': notableEvents,
      'faculty': faculty.map((f) => f.toJson()).toList(),
      'rooms': rooms.map((r) => r.toJson()).toList(),
      'departments': departments,
      'campusRegion': campusRegion,
      'reserveRoomUrl': reserveRoomUrl,
    };
  }

  // Equatable needs this — tells BLoC how to compare two Building objects
  @override
  List<Object?> get props => [id, name, type, latitude, longitude];
}

// Faculty member inside a university building
class Faculty extends Equatable {
  final String name;
  final String? title;
  final String? department;
  final String? officeRoom;
  final String? email;
  final String? phone;
  final String? imageUrl;

  const Faculty({
    required this.name,
    this.title,
    this.department,
    this.officeRoom,
    this.email,
    this.phone,
    this.imageUrl,
  });

  factory Faculty.fromJson(Map<String, dynamic> json) {
    return Faculty(
      name: json['name'] as String,
      title: json['title'] as String?,
      department: json['department'] as String?,
      officeRoom: json['officeRoom'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'title': title,
      'department': department,
      'officeRoom': officeRoom,
      'email': email,
      'phone': phone,
      'imageUrl': imageUrl,
    };
  }

  @override
  List<Object?> get props => [name, department, officeRoom];
}

// Room inside a building
class Room extends Equatable {
  final String number;
  final String? name;
  final String? type; // office, classroom, auditorium, lab
  final int? floor;
  final int? capacity;

  const Room({
    required this.number,
    this.name,
    this.type,
    this.floor,
    this.capacity,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      number: json['number'] as String,
      name: json['name'] as String?,
      type: json['type'] as String?,
      floor: json['floor'] as int?,
      capacity: json['capacity'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'name': name,
      'type': type,
      'floor': floor,
      'capacity': capacity,
    };
  }

  @override
  List<Object?> get props => [number, name];
}
