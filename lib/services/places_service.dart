import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlacesService {
  final String apiKey;

  PlacesService({required this.apiKey});

  static const Map<String, String> categoryTypes = {
    'All': '',
    'Restaurants': 'restaurant',
    'Cafes': 'cafe',
    'Shopping': 'shopping_mall|store|clothing_store',
    'Banks': 'bank|atm',
    'Entertainment': 'movie_theater|bowling_alley|amusement_park',
    'Gas Stations': 'gas_station',
    'Grocery': 'supermarket|grocery_or_supermarket',
    'Pharmacy': 'pharmacy',
    'Hotels': 'lodging',
    'Gyms': 'gym',
    'Parks': 'park',
  };

  Future<List<NearbyPlace>> getNearbyPlaces(
    double latitude,
    double longitude, {
    int radius = 3200,
    String category = 'All',
  }) async {
    String typeParam = '';
    final type = categoryTypes[category] ?? '';
    if (type.isNotEmpty) {
      typeParam = '&type=${type.split('|').first}';
      if (type.contains('|')) {
        typeParam = '&keyword=${category.toLowerCase()}';
      }
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$latitude,$longitude'
      '&radius=$radius'
      '$typeParam'
      '&key=$apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>;
        return results
            .map((r) => NearbyPlace.fromJson(r, apiKey, latitude, longitude))
            .toList();
      }
    } catch (e) {
      print('Places API error: $e');
    }
    return [];
  }

  /// Fetch walking route polyline from Google Directions API
  Future<List<LatLng>> getWalkingRoute(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&mode=walking'
      '&key=$apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final encodedPolyline =
              data['routes'][0]['overview_polyline']['points'];
          return _decodePolyline(encodedPolyline);
        }
      }
    } catch (e) {
      print('Directions API error: $e');
    }
    return [];
  }

  /// Search for a building by name near given coordinates and return its photo URL
  Future<String?> getBuildingPhoto(
    String buildingName,
    double latitude,
    double longitude, {
    int maxWidth = 800,
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$latitude,$longitude'
      '&radius=200'
      '&keyword=${Uri.encodeComponent(buildingName)}'
      '&key=$apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>;
        if (results.isNotEmpty) {
          final photos = results[0]['photos'] as List<dynamic>?;
          if (photos != null && photos.isNotEmpty) {
            final photoRef = photos[0]['photo_reference'] as String;
            return 'https://maps.googleapis.com/maps/api/place/photo'
                '?maxwidth=$maxWidth'
                '&photo_reference=$photoRef'
                '&key=$apiKey';
          }
        }
      }
    } catch (e) {
      print('Places photo error: $e');
    }
    return null;
  }

  /// Decode Google's encoded polyline string into LatLng points
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}

class NearbyPlace {
  final String placeId;
  final String name;
  final double? rating;
  final int? totalRatings;
  final String? vicinity;
  final bool? isOpen;
  final List<String> types;
  final String? photoUrl;
  final double latitude;
  final double longitude;
  final int? priceLevel;
  final double distanceMeters;

  NearbyPlace({
    required this.placeId,
    required this.name,
    this.rating,
    this.totalRatings,
    this.vicinity,
    this.isOpen,
    required this.types,
    this.photoUrl,
    required this.latitude,
    required this.longitude,
    this.priceLevel,
    required this.distanceMeters,
  });

  factory NearbyPlace.fromJson(
    Map<String, dynamic> json,
    String apiKey,
    double userLat,
    double userLng,
  ) {
    String? photoUrl;
    if (json['photos'] != null && (json['photos'] as List).isNotEmpty) {
      final photoRef = json['photos'][0]['photo_reference'];
      photoUrl =
          'https://maps.googleapis.com/maps/api/place/photo?maxwidth=200&photo_reference=$photoRef&key=$apiKey';
    }

    final lat = json['geometry']['location']['lat'].toDouble();
    final lng = json['geometry']['location']['lng'].toDouble();

    return NearbyPlace(
      placeId: json['place_id'] ?? '',
      name: json['name'] ?? '',
      rating: (json['rating'] as num?)?.toDouble(),
      totalRatings: json['user_ratings_total'] as int?,
      vicinity: json['vicinity'] as String?,
      isOpen: json['opening_hours']?['open_now'] as bool?,
      types: List<String>.from(json['types'] ?? []),
      photoUrl: photoUrl,
      latitude: lat,
      longitude: lng,
      priceLevel: json['price_level'] as int?,
      distanceMeters: _calculateDistance(userLat, userLng, lat, lng),
    );
  }

  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String get distanceString {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get priceString {
    if (priceLevel == null) return '';
    return '\$' * priceLevel!;
  }

  String get typeLabel {
    if (types.contains('restaurant')) return 'Restaurant';
    if (types.contains('cafe')) return 'Cafe';
    if (types.contains('bank') || types.contains('atm')) return 'Bank';
    if (types.contains('shopping_mall') || types.contains('store'))
      return 'Shopping';
    if (types.contains('movie_theater')) return 'Entertainment';
    if (types.contains('gas_station')) return 'Gas Station';
    if (types.contains('supermarket')) return 'Grocery';
    if (types.contains('pharmacy')) return 'Pharmacy';
    if (types.contains('lodging')) return 'Hotel';
    if (types.contains('gym')) return 'Gym';
    if (types.contains('park')) return 'Park';
    if (types.contains('food')) return 'Food';
    return 'Place';
  }

  IconLabel get iconInfo {
    if (types.contains('restaurant') || types.contains('food'))
      return IconLabel(0xe56c, 'restaurant');
    if (types.contains('cafe')) return IconLabel(0xe541, 'coffee');
    if (types.contains('bank') || types.contains('atm'))
      return IconLabel(0xe069, 'bank');
    if (types.contains('shopping_mall') || types.contains('store'))
      return IconLabel(0xe8d1, 'store');
    if (types.contains('movie_theater')) return IconLabel(0xe02c, 'movie');
    if (types.contains('gas_station')) return IconLabel(0xe546, 'gas');
    if (types.contains('supermarket')) return IconLabel(0xf37d, 'grocery');
    if (types.contains('pharmacy')) return IconLabel(0xe548, 'pharmacy');
    if (types.contains('lodging')) return IconLabel(0xe53a, 'hotel');
    if (types.contains('gym')) return IconLabel(0xeb43, 'gym');
    if (types.contains('park')) return IconLabel(0xea00, 'park');
    return IconLabel(0xe55f, 'place');
  }
}

class IconLabel {
  final int codePoint;
  final String label;
  IconLabel(this.codePoint, this.label);
}
