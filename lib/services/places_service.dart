import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

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
