import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/building.dart';
import '../../services/building_service.dart';
import '../../services/location_service.dart';
import '../../services/places_service.dart';
import '../../utils/helpers.dart';
import '../../utils/constants.dart';
import 'building_detail_screen.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/library_search_service.dart';
import '../../services/indoor_position_service.dart';
import '../../services/indoor_navigation_service.dart';

// ── Bird Library Constants ──
const double _birdLibLat = 43.0398955;
const double _birdLibLng = -76.1326052;
const double _birdLibDetectionRadius = 50; // meters

const List<String> _floorIds = ['B', '1', '2', '3', '4', '5', '6'];
const List<String> _floorLabels = [
  'Lower Level (B)',
  'First Floor (1)',
  'Second Floor (2)',
  'Third Floor (3)',
  'Fourth Floor (4)',
  'Fifth Floor (5)',
  'Sixth Floor (6)',
];
const List<String> _floorAssets = [
  'assets/library_maps/bird_floor_B.jpg',
  'assets/library_maps/bird_floor_1.jpg',
  'assets/library_maps/bird_floor_2.jpg',
  'assets/library_maps/bird_floor_3.jpg',
  'assets/library_maps/bird_floor_4.jpg',
  'assets/library_maps/bird_floor_5.jpg',
  'assets/library_maps/bird_floor_6.jpg',
];

class CameraScreen extends StatefulWidget {
  final Building? navigationTarget;
  const CameraScreen({super.key, this.navigationTarget});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final LocationService _locationService = LocationService();
  final BuildingService _buildingService = BuildingService();
  final PlacesService _placesService = PlacesService(
    apiKey: 'AIzaSyD3LT18vanu6-6ONyTjQHql9fRocSCFR-c',
  );

  Building? _detectedBuilding;
  String? _distance;
  bool _isInitialized = false;

  // Nearby places state
  List<NearbyPlace> _nearbyPlaces = [];
  bool _placesLoading = false;
  bool _showPlaces = false;
  String _selectedCategory = 'All';
  String _sortBy = 'nearest';

  // AR navigation state
  NearbyPlace? _navigationTarget;
  Position? _currentPosition;
  GoogleMapController? _miniMapController;
  List<LatLng> _routePoints = [];
  double _miniMapZoom = 16;
  List<Building> _allBuildings = [];
  Building? _pointedAtBuilding;
  String? _pointedAtDistance;
  String? _pointedAtPhotoUrl;

  // ── Bird Library Indoor Mode ──
  bool _isInsideBirdLibrary = false;
  bool _indoorModeActive = false;
  int _selectedFloorIndex = 1; // default to First Floor
  Map<String, dynamic>? _birdLibraryData;
  Map<String, Map<String, String>>? _compassGuides;
  final LibrarySearchService _librarySearch = LibrarySearchService();
  LibrarySearchResult? _activeRoomGuide;
  TransitOption? _selectedTransit;
  int _currentLegIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startLocationUpdates();
    _loadBirdLibraryData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _loadBirdLibraryData() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/data/bird_library_indoor.json',
      );
      final data = json.decode(jsonString) as Map<String, dynamic>;
      final guides = <String, Map<String, String>>{};
      final floorGuides =
          data['compassGuide']?['floorGuides'] as Map<String, dynamic>?;
      if (floorGuides != null) {
        for (final entry in floorGuides.entries) {
          guides[entry.key] = Map<String, String>.from(entry.value);
        }
      }
      setState(() {
        _birdLibraryData = data;
        _compassGuides = guides;
      });
      await _librarySearch.load();
    } catch (e) {
      debugPrint('Error loading Bird Library data: $e');
    }
  }

  void _checkBirdLibraryProximity() {
    if (_currentPosition == null) return;
    final dist = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _birdLibLat,
      _birdLibLng,
    );
    final inside = dist <= _birdLibDetectionRadius;
    if (inside != _isInsideBirdLibrary) {
      setState(() {
        _isInsideBirdLibrary = inside;
        if (!inside) _indoorModeActive = false;
      });
    }
  }

  String _getCompassDirection(double heading) {
    // Adjust for building rotation (~-15° from true north)
    final adjusted = (heading + 15) % 360;
    if (adjusted >= 337.5 || adjusted < 22.5) return 'north';
    if (adjusted >= 22.5 && adjusted < 67.5) return 'northeast';
    if (adjusted >= 67.5 && adjusted < 112.5) return 'east';
    if (adjusted >= 112.5 && adjusted < 157.5) return 'southeast';
    if (adjusted >= 157.5 && adjusted < 202.5) return 'south';
    if (adjusted >= 202.5 && adjusted < 247.5) return 'southwest';
    if (adjusted >= 247.5 && adjusted < 292.5) return 'west';
    return 'northwest';
  }

  String _getDirectionLabel(String direction) {
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
    return labels[direction] ?? direction;
  }

  String? _getCompassGuideText(double heading) {
    if (_compassGuides == null) return null;
    final floorId = _floorIds[_selectedFloorIndex];
    final floorGuide = _compassGuides![floorId];
    if (floorGuide == null) return null;
    final direction = _getCompassDirection(heading);
    return floorGuide[direction];
  }

  void _showFloorSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Which floor are you on?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Bird Library Indoor Guide',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _floorLabels.length,
                  itemBuilder: (context, index) {
                    final isSelected = _selectedFloorIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedFloorIndex = index;
                          _indoorModeActive = true;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? const Color(0xFFD44500)
                                  : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isSelected
                                    ? const Color(0xFFD44500)
                                    : Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getFloorIcon(index),
                              color:
                                  isSelected ? Colors.white : Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _floorLabels[index],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getFloorIcon(int index) {
    switch (index) {
      case 0:
        return Icons.stairs; // Lower Level
      case 1:
        return Icons.coffee; // First Floor (Pages Café)
      case 2:
        return Icons.menu_book; // Second Floor (Periodicals)
      case 3:
        return Icons.map; // Third Floor (Map Room)
      case 4:
        return Icons.music_note; // Fourth Floor (Music/Media)
      case 5:
        return Icons.language; // Fifth Floor (Languages/Lit)
      case 6:
        return Icons.archive; // Sixth Floor (Special Collections)
      default:
        return Icons.layers;
    }
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _startLocationUpdates() async {
    final hasPermission = await _locationService.requestPermission();
    if (!hasPermission) return;
    final pos = await _locationService.getCurrentPosition();
    _currentPosition = pos;

    _allBuildings = await _buildingService.getAllBuildings();

    if (widget.navigationTarget != null) {
      _startBuildingNavigation();
    }

    // Check Bird Library proximity on first position
    _checkBirdLibraryProximity();

    _locationService.getPositionStream().listen((position) async {
      _currentPosition = position;

      // Check Bird Library proximity on every update
      _checkBirdLibraryProximity();

      final buildings = await _buildingService.getAllBuildings();

      Building? nearest;
      double minDist = double.infinity;

      for (final b in buildings) {
        final dist = Helpers.calculateDistance(
          position.latitude,
          position.longitude,
          b.latitude,
          b.longitude,
        );
        if (dist < minDist) {
          minDist = dist;
          nearest = b;
        }
      }

      if (mounted) {
        setState(() {
          if (nearest != null &&
              minDist < AppConstants.buildingDetectionRadius) {
            _detectedBuilding = nearest;
            _distance = Helpers.formatDistance(minDist);
          } else {
            _detectedBuilding = null;
            _distance = null;
          }
        });
      }
    });
  }

  Future<void> _startBuildingNavigation() async {
    final building = widget.navigationTarget;
    if (building == null || _currentPosition == null) return;

    final distance = Helpers.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      building.latitude,
      building.longitude,
    );

    final targetPlace = NearbyPlace(
      placeId: building.id,
      name: building.name,
      rating: null,
      totalRatings: null,
      vicinity: building.address,
      isOpen: null,
      types: [building.type.name],
      photoUrl: null,
      latitude: building.latitude,
      longitude: building.longitude,
      priceLevel: null,
      distanceMeters: distance,
    );

    final points = await _placesService.getWalkingRoute(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      building.latitude,
      building.longitude,
    );

    if (mounted) {
      setState(() {
        _navigationTarget = targetPlace;
        _routePoints = points;
      });
    }
  }

  void _updatePointedAtBuilding(double heading) {
    if (_currentPosition == null || _allBuildings.isEmpty) return;
    if (_navigationTarget != null) return;
    if (_indoorModeActive) return; // don't detect buildings in indoor mode

    Building? best;
    double bestAngleDiff = 20;
    double bestDist = 0;

    for (final b in _allBuildings) {
      final dist = Helpers.calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        b.latitude,
        b.longitude,
      );
      if (dist > 800) continue;

      final bearing = _calculateBearing(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        b.latitude,
        b.longitude,
      );

      double diff = (bearing - heading).abs();
      if (diff > 180) diff = 360 - diff;

      if (diff < bestAngleDiff) {
        bestAngleDiff = diff;
        best = b;
        bestDist = dist;
      }
    }

    if (best != null && best.id != _pointedAtBuilding?.id) {
      setState(() {
        _pointedAtBuilding = best;
        _pointedAtDistance = Helpers.formatDistance(bestDist);
        _pointedAtPhotoUrl = null;
      });
      _placesService
          .getBuildingPhoto(best.name, best.latitude, best.longitude)
          .then((url) {
            if (mounted && _pointedAtBuilding?.id == best!.id) {
              setState(() => _pointedAtPhotoUrl = url);
            }
          });
    } else if (best == null) {
      if (_pointedAtBuilding != null) {
        setState(() {
          _pointedAtBuilding = null;
          _pointedAtDistance = null;
          _pointedAtPhotoUrl = null;
        });
      }
    }
  }

  Future<void> _loadNearbyPlaces() async {
    setState(() => _placesLoading = true);

    final position = await _locationService.getCurrentPosition();
    final places = await _placesService.getNearbyPlaces(
      position.latitude,
      position.longitude,
      radius: 5000,
      category: _selectedCategory,
    );

    if (mounted) {
      setState(() {
        _nearbyPlaces = places;
        _placesLoading = false;
        _sortPlaces();
      });
    }
  }

  void _sortPlaces() {
    if (_sortBy == 'nearest') {
      _nearbyPlaces.sort(
        (a, b) => a.distanceMeters.compareTo(b.distanceMeters),
      );
    } else {
      _nearbyPlaces.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    }
  }

  void _showExploreSheet() {
    _loadNearbyPlaces();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _ExploreSheet(
            places: _nearbyPlaces,
            loading: _placesLoading,
            selectedCategory: _selectedCategory,
            sortBy: _sortBy,
            onCategoryChanged: (cat) {
              _selectedCategory = cat;
              _loadNearbyPlaces();
            },
            onSortChanged: (sort) {
              setState(() {
                _sortBy = sort;
                _sortPlaces();
              });
            },
            onPlaceSelected: (place) async {
              Navigator.pop(context);
              setState(() => _navigationTarget = place);
              final points = await _placesService.getWalkingRoute(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                place.latitude,
                place.longitude,
              );
              setState(() {
                _routePoints = points;
              });
            },
            onDirections: (place) async {
              final url = Uri.parse(
                'https://www.google.com/maps/dir/?api=1&destination=${place.latitude},${place.longitude}&travelmode=walking',
              );
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            parentState: this,
          ),
    );
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180;
    final lat1Rad = lat1 * pi / 180;
    final lat2Rad = lat2 * pi / 180;
    final y = sin(dLon) * cos(lat2Rad);
    final x =
        cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _getZoomForDistance(double meters) {
    if (meters > 5000) return 12;
    if (meters > 2000) return 13;
    if (meters > 1000) return 14;
    if (meters > 500) return 15;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Starting camera...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),

        // AR Building Recognition overlay (only when NOT in indoor mode)
        if (_navigationTarget == null && !_indoorModeActive)
          StreamBuilder<CompassEvent>(
            stream: FlutterCompass.events,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.heading != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _updatePointedAtBuilding(snapshot.data!.heading!);
                });
              }
              return const SizedBox.shrink();
            },
          ),

        // Building AR label when pointing at a building (NOT in indoor mode)
        if (_pointedAtBuilding != null &&
            _navigationTarget == null &&
            !_indoorModeActive)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.3,
            left: 24,
            right: 24,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) =>
                            BuildingDetailScreen(building: _pointedAtBuilding!),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFD44500).withOpacity(0.6),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child:
                          _pointedAtPhotoUrl != null
                              ? Image.network(
                                _pointedAtPhotoUrl!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, __, ___) => Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFD44500,
                                        ).withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.school,
                                        color: Color(0xFFD44500),
                                        size: 30,
                                      ),
                                    ),
                              )
                              : Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFD44500,
                                  ).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.school,
                                  color: Color(0xFFD44500),
                                  size: 30,
                                ),
                              ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _pointedAtBuilding!.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pointedAtBuilding!.type.name.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFD44500),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.directions_walk,
                                color: Colors.green,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _pointedAtDistance ?? '',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Tap to view details →',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── INDOOR MODE: Floor map + compass guide ──
        if (_indoorModeActive && _navigationTarget == null)
          _buildIndoorModeOverlay(),

        // AR Navigation arrow (outdoor navigation)
        if (_navigationTarget != null &&
            _currentPosition != null &&
            !_indoorModeActive)
          _buildNavigationOverlay(),

        // ── Top bar ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _indoorModeActive
                      ? Icons.apartment
                      : _navigationTarget != null
                      ? Icons.navigation
                      : _detectedBuilding != null
                      ? Icons.location_on
                      : Icons.gps_fixed,
                  color:
                      _indoorModeActive
                          ? Colors.blue
                          : _navigationTarget != null
                          ? Colors.green
                          : _detectedBuilding != null
                          ? const Color(0xFFD44500)
                          : Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _indoorModeActive
                        ? 'Bird Library · ${_floorLabels[_selectedFloorIndex]}'
                        : _navigationTarget != null
                        ? 'Navigating to ${_navigationTarget!.name}'
                        : _detectedBuilding != null
                        ? 'Building detected nearby!'
                        : 'Point at a building...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_indoorModeActive)
                  GestureDetector(
                    onTap: () => setState(() => _indoorModeActive = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Exit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else if (_navigationTarget != null)
                  GestureDetector(
                    onTap:
                        () => setState(() {
                          _navigationTarget = null;
                          _routePoints = [];
                          _miniMapZoom = 16;
                        }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Stop',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bird Library indoor button (shows when near Bird Library)
                      if (_isInsideBirdLibrary) ...[
                        GestureDetector(
                          onTap: _showFloorSelector,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.apartment,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Indoor',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GestureDetector(
                        onTap: _showExploreSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD44500),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.explore,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Explore',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),

        // Building detection card (NOT in indoor mode)
        if (_detectedBuilding != null &&
            _navigationTarget == null &&
            !_indoorModeActive)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) =>
                            BuildingDetailScreen(building: _detectedBuilding!),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD44500).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.school,
                        color: Color(0xFFD44500),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _detectedBuilding!.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _detectedBuilding!.type.name.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFD44500),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _detectedBuilding!.description ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _distance ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFD44500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ══════════════════════════════════════════════════
  // ── INDOOR MODE OVERLAY (Bird Library) ──
  // ══════════════════════════════════════════════════

  void _showRoomSearch() {
    String query = '';
    List<LibrarySearchResult> results = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Text(
                      'Find a Room',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Search by room number, name, or amenity',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Search input
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'e.g. 403, Map Room, printer, café...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFFD44500),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          query = value;
                          results = _librarySearch.search(value);
                        });
                      },
                    ),
                    const SizedBox(height: 8),

                    // Quick search chips
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _quickChip('Printer', Icons.print, () {
                            setSheetState(() {
                              query = 'printer';
                              results = _librarySearch.search('printer');
                            });
                          }),
                          _quickChip('Restroom', Icons.wc, () {
                            setSheetState(() {
                              query = 'restroom';
                              results = _librarySearch.search('restroom');
                            });
                          }),
                          _quickChip('Quiet Space', Icons.volume_off, () {
                            setSheetState(() {
                              query = 'quiet';
                              results = _librarySearch.search('quiet');
                            });
                          }),
                          _quickChip('Café', Icons.coffee, () {
                            setSheetState(() {
                              query = 'cafe';
                              results = _librarySearch.search('cafe');
                            });
                          }),
                          _quickChip('Team Room', Icons.groups, () {
                            setSheetState(() {
                              query = 'team';
                              results = _librarySearch.search('team');
                            });
                          }),
                          _quickChip('Study Room', Icons.menu_book, () {
                            setSheetState(() {
                              query = 'study';
                              results = _librarySearch.search('study');
                            });
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Results count
                    if (query.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${results.length} result${results.length == 1 ? '' : 's'} found',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),

                    // Results list
                    Flexible(
                      child:
                          results.isEmpty && query.isNotEmpty
                              ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'No rooms or spaces found',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              : ListView.builder(
                                shrinkWrap: true,
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final r = results[index];
                                  return _buildSearchResultTile(r, context);
                                },
                              ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _quickChip(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFFD44500)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultTile(LibrarySearchResult r, BuildContext ctx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pop(ctx);
          if (r.floorIndex != _selectedFloorIndex) {
            setState(() {
              _activeRoomGuide = r;
              _selectedTransit = null;
              _currentLegIndex = 0;
            });
            _showTransitChoice(r);
          } else {
            setState(() {
              _activeRoomGuide = r;
              _selectedTransit = null;
              _currentLegIndex = 0;
              _indoorModeActive = true;
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD44500).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getResultIcon(r.type),
                  color: const Color(0xFFD44500),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r.floorLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r.typeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Direction badge
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD44500),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.compass_calibration,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          r.shortDirection,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getResultIcon(String type) {
    switch (type) {
      case 'study_room':
        return Icons.menu_book;
      case 'open_study':
        return Icons.weekend;
      case 'quiet_space':
        return Icons.volume_off;
      case 'book_stacks':
        return Icons.library_books;
      case 'service_desk':
        return Icons.support_agent;
      case 'dining':
      case 'amenity_dining':
        return Icons.coffee;
      case 'technology':
        return Icons.computer;
      case 'office':
        return Icons.business;
      case 'classroom':
        return Icons.school;
      case 'student_success':
        return Icons.emoji_people;
      case 'faculty_success':
        return Icons.person;
      case 'special_collection':
        return Icons.auto_stories;
      case 'exhibition':
        return Icons.museum;
      case 'meeting_room':
        return Icons.meeting_room;
      case 'learning_commons':
        return Icons.groups;
      case 'scholarly_commons':
        return Icons.science;
      case 'amenity_printer':
        return Icons.print;
      case 'amenity_restroom':
        return Icons.wc;
      case 'amenity_water':
        return Icons.water_drop;
      case 'amenity_quiet':
        return Icons.volume_off;
      default:
        return Icons.place;
    }
  }

  void _showTransitChoice(LibrarySearchResult target) {
    final options = IndoorNavigationService.getTransitOptions(
      _selectedFloorIndex,
      target.floorIndex,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'How do you want to get to ${target.name}?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${_floorLabels[_selectedFloorIndex]} → ${target.floorLabel}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ...options.map((option) {
                final isElevator = option.type == TransitChoice.elevator;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTransit = option;
                      _currentLegIndex = 0;
                      _indoorModeActive = true;
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          isElevator
                              ? Colors.blue.withOpacity(0.05)
                              : Colors.green.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            isElevator
                                ? Colors.blue.withOpacity(0.3)
                                : Colors.green.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isElevator ? Colors.blue : Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isElevator ? Icons.elevator : Icons.stairs,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                option.subtitle,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                              if (option.legs.length > 1) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${option.legs.length} steps',
                                  style: TextStyle(
                                    color:
                                        isElevator ? Colors.blue : Colors.green,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Room Guide Card (shows when user selected a room from search) ──
  Widget _buildRoomGuideCard() {
    if (_activeRoomGuide == null) return const SizedBox.shrink();
    final r = _activeRoomGuide!;
    final bool sameFloor = r.floorIndex == _selectedFloorIndex;

    // Same floor or no transit selected yet — simple card
    if (sameFloor && _selectedTransit == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFD44500).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD44500).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFD44500),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getResultIcon(r.type),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Face ${r.directionLabel} · ${r.floorLabel}',
                    style: const TextStyle(
                      color: Color(0xFFD44500),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap:
                  () => setState(() {
                    _activeRoomGuide = null;
                    _selectedTransit = null;
                  }),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.close, color: Colors.white54, size: 16),
              ),
            ),
          ],
        ),
      );
    }

    // No transit chosen yet but different floor — prompt to choose
    if (_selectedTransit == null) {
      return GestureDetector(
        onTap: () => _showTransitChoice(r),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.swap_vert,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tap to choose: Elevator or Stairs?',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap:
                    () => setState(() {
                      _activeRoomGuide = null;
                      _selectedTransit = null;
                    }),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Active multi-leg navigation ──
    final transit = _selectedTransit!;
    final legIndex = _currentLegIndex.clamp(0, transit.legs.length - 1);
    final currentLeg = transit.legs[legIndex];
    final isLastLeg = legIndex == transit.legs.length - 1;

    NavigationInstruction instruction;
    if (_currentPosition != null) {
      instruction = IndoorNavigationService.getLegInstruction(
        userLat: _currentPosition!.latitude,
        userLng: _currentPosition!.longitude,
        leg: currentLeg,
        currentFloorIndex: _selectedFloorIndex,
        finalRoomName: r.name,
        finalDirection: r.directionLabel,
        finalFloorLabel: r.floorLabel,
        isLastLeg: isLastLeg,
      );
    } else {
      instruction = NavigationInstruction(
        phase: NavPhase.walkingToTransit,
        message: 'Head to ${currentLeg.label}',
        detail: null,
        showArrow: false,
      );
    }

    // Determine card color
    final Color cardColor;
    final IconData cardIcon;
    if (instruction.phase == NavPhase.atTransit) {
      cardColor = Colors.green;
      cardIcon =
          currentLeg.transitType == TransitType.elevator
              ? Icons.elevator
              : Icons.stairs;
    } else {
      cardColor =
          currentLeg.transitType == TransitType.elevator
              ? Colors.blue
              : Colors.green;
      cardIcon =
          currentLeg.transitType == TransitType.elevator
              ? Icons.elevator
              : currentLeg.transitType == TransitType.walkToTransfer
              ? Icons.directions_walk
              : Icons.stairs;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress indicator
          if (transit.legs.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: List.generate(transit.legs.length, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color:
                            i <= legIndex
                                ? cardColor
                                : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(cardIcon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      instruction.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (instruction.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        instruction.detail!,
                        style: TextStyle(
                          color: cardColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap:
                    () => setState(() {
                      _activeRoomGuide = null;
                      _selectedTransit = null;
                      _currentLegIndex = 0;
                    }),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),

          // "Switch Floor" or "Next Step" button
          if (instruction.isAtTransitReady) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (instruction.switchToFloor != null) {
                    _selectedFloorIndex = instruction.switchToFloor!;
                  }
                  if (_currentLegIndex < transit.legs.length - 1) {
                    _currentLegIndex++;
                  } else {
                    // Last leg done — arrived!
                    _selectedTransit = null;
                    _currentLegIndex = 0;
                  }
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLastLeg ? Icons.swap_vert : Icons.arrow_forward,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      instruction.switchToFloor != null
                          ? 'Switch to ${_floorLabels[instruction.switchToFloor!]}'
                          : isLastLeg
                          ? 'Arrived!'
                          : 'Next Step',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIndoorModeOverlay() {
    // Calculate navigation instruction for AR arrow
    NavigationInstruction? navInstruction;
    if (_activeRoomGuide != null &&
        _selectedTransit != null &&
        _currentPosition != null) {
      final legIndex = _currentLegIndex.clamp(
        0,
        _selectedTransit!.legs.length - 1,
      );
      final currentLeg = _selectedTransit!.legs[legIndex];
      final isLastLeg = legIndex == _selectedTransit!.legs.length - 1;
      navInstruction = IndoorNavigationService.getLegInstruction(
        userLat: _currentPosition!.latitude,
        userLng: _currentPosition!.longitude,
        leg: currentLeg,
        currentFloorIndex: _selectedFloorIndex,
        finalRoomName: _activeRoomGuide!.name,
        finalDirection: _activeRoomGuide!.directionLabel,
        finalFloorLabel: _activeRoomGuide!.floorLabel,
        isLastLeg: isLastLeg,
      );
    }

    return Stack(
      children: [
        // ── Rotating floor map ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 65,
          right: 16,
          child: Column(
            children: [
              StreamBuilder<CompassEvent>(
                stream: FlutterCompass.events,
                builder: (context, snapshot) {
                  double heading = 0;
                  if (snapshot.hasData && snapshot.data!.heading != null) {
                    heading = snapshot.data!.heading!;
                  }

                  final mapRotation = -(heading - 345) * pi / 180;

                  // ── GPS floor position ──
                  double dotX = 0.5; // default center
                  double dotY = 0.5;
                  bool hasGpsPosition = false;

                  if (_currentPosition != null) {
                    final pos = IndoorPositionService.getFloorPosition(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    );
                    if (pos != null) {
                      dotX = pos.x;
                      dotY = pos.y;
                      hasGpsPosition = true;
                    }
                  }

                  // Convert floor position (0-1) to Alignment (-1 to 1)
                  // Also rotate the dot position with the map so it stays
                  // aligned with the rotated floor plan
                  final rawAlignX = (dotX * 2) - 1; // 0->-1, 0.5->0, 1->1
                  final rawAlignY = (dotY * 2) - 1;

                  // Rotate the dot position by the same angle as the map
                  final cosA = cos(mapRotation);
                  final sinA = sin(mapRotation);
                  final rotatedX = rawAlignX * cosA - rawAlignY * sinA;
                  final rotatedY = rawAlignX * sinA + rawAlignY * cosA;

                  // Scale by 1.5 to match the Transform.scale on the map
                  final scaledX = (rotatedX * 1.5).clamp(-1.0, 1.0);
                  final scaledY = (rotatedY * 1.5).clamp(-1.0, 1.0);

                  return Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        children: [
                          // Rotating floor map image
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: Transform.rotate(
                              angle: mapRotation,
                              child: Transform.scale(
                                scale: 1.5,
                                child: Image.asset(
                                  _floorAssets[_selectedFloorIndex],
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) => Container(
                                        color: Colors.grey[900],
                                        child: const Center(
                                          child: Icon(
                                            Icons.map,
                                            color: Colors.white38,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ),

                          // Edge fade overlay
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.4),
                                ],
                                stops: const [0.0, 0.7, 1.0],
                              ),
                            ),
                          ),

                          // Direction indicator at top
                          Align(
                            alignment: const Alignment(0, -0.88),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getDirectionLabel(
                                  _getCompassDirection(heading),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                          // ── GPS-based "You" dot ──
                          Align(
                            alignment: Alignment(scaledX, scaledY),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // GPS accuracy pulse ring (shows GPS is active)
                          if (hasGpsPosition)
                            Align(
                              alignment: Alignment(scaledX, scaledY),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue.withOpacity(0.15),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),

                          // Floor label badge
                          Align(
                            alignment: const Alignment(0, 0.85),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _floorIds[_selectedFloorIndex] == 'B'
                                    ? 'Lower Level'
                                    : 'Floor ${_floorIds[_selectedFloorIndex]}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 8),

              // Switch Floor + Search buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _showFloorSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Floor',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _showRoomSearch,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD44500).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Find Room',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Indoor AR Arrow ──
        if (navInstruction != null &&
            navInstruction.showArrow &&
            navInstruction.targetLat != null &&
            _currentPosition != null)
          Positioned.fill(
            child: StreamBuilder<CompassEvent>(
              stream: FlutterCompass.events,
              builder: (context, snapshot) {
                double heading = 0;
                if (snapshot.hasData && snapshot.data!.heading != null) {
                  heading = snapshot.data!.heading!;
                }
                final bearing = IndoorNavigationService.bearingTo(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  navInstruction!.targetLat!,
                  navInstruction.targetLng!,
                );
                final relativeAngle = (bearing - heading) * pi / 180;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Transform.rotate(
                      angle: relativeAngle,
                      child: CustomPaint(
                        size: const Size(100, 100),
                        painter: _IndoorArrowPainter(
                          isElevator:
                              navInstruction.transitType ==
                              TransitType.elevator,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // ── Compass guide info card ──
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: StreamBuilder<CompassEvent>(
            stream: FlutterCompass.events,
            builder: (context, snapshot) {
              double heading = 0;
              if (snapshot.hasData && snapshot.data!.heading != null) {
                heading = snapshot.data!.heading!;
              }

              final direction = _getCompassDirection(heading);
              final dirLabel = _getDirectionLabel(direction);
              final guideText = _getCompassGuideText(heading);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Room guide card (when searching for a specific room)
                  if (_activeRoomGuide != null) _buildRoomGuideCard(),

                  // General compass guide
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.compass_calibration,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Facing $dirLabel',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _floorLabels[_selectedFloorIndex],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${heading.toInt()}°',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        if (guideText != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.blue,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  guideText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.apartment,
                              color: Colors.white38,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Bird Library Indoor Guide',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _showRoomSearch,
                              child: const Text(
                                'Find Room →',
                                style: TextStyle(
                                  color: Color(0xFFD44500),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════
  // ── OUTDOOR NAVIGATION OVERLAY (existing) ──
  // ══════════════════════════════════════════════════
  Widget _buildNavigationOverlay() {
    if (_miniMapZoom == 16 && _navigationTarget != null) {
      _miniMapZoom = _getZoomForDistance(_navigationTarget!.distanceMeters);
    }

    return Stack(
      children: [
        // GTA-style live mini-map
        Positioned(
          top: MediaQuery.of(context).padding.top + 65,
          right: 16,
          child: Column(
            children: [
              StreamBuilder<CompassEvent>(
                stream: FlutterCompass.events,
                builder: (context, snapshot) {
                  double heading = 0;
                  if (snapshot.hasData && snapshot.data!.heading != null) {
                    heading = snapshot.data!.heading!;
                  }

                  if (_miniMapController != null && _currentPosition != null) {
                    _miniMapController!.moveCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(
                          target: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          zoom: _miniMapZoom,
                          bearing: heading,
                        ),
                      ),
                    );
                  }

                  return Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD44500),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        children: [
                          SizedBox(
                            width: 170,
                            height: 170,
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(
                                  _currentPosition!.latitude,
                                  _currentPosition!.longitude,
                                ),
                                zoom: _miniMapZoom,
                                bearing: heading,
                              ),
                              markers: {
                                Marker(
                                  markerId: const MarkerId('destination'),
                                  position: LatLng(
                                    _navigationTarget!.latitude,
                                    _navigationTarget!.longitude,
                                  ),
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueRed,
                                  ),
                                ),
                              },
                              polylines: {
                                Polyline(
                                  polylineId: const PolylineId('route'),
                                  points:
                                      _routePoints.isNotEmpty
                                          ? _routePoints
                                          : [
                                            LatLng(
                                              _currentPosition!.latitude,
                                              _currentPosition!.longitude,
                                            ),
                                            LatLng(
                                              _navigationTarget!.latitude,
                                              _navigationTarget!.longitude,
                                            ),
                                          ],
                                  color: const Color(0xFF4285F4),
                                  width: 4,
                                ),
                              },
                              myLocationEnabled: true,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              compassEnabled: false,
                              scrollGesturesEnabled: false,
                              zoomGesturesEnabled: false,
                              rotateGesturesEnabled: false,
                              tiltGesturesEnabled: false,
                              liteModeEnabled: false,
                              onMapCreated: (controller) {
                                _miniMapController = controller;
                                controller.animateCamera(
                                  CameraUpdate.newCameraPosition(
                                    CameraPosition(
                                      target: LatLng(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                      ),
                                      zoom: _miniMapZoom,
                                      bearing: heading,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.3),
                                ],
                                stops: const [0.0, 0.75, 1.0],
                              ),
                            ),
                          ),
                          Align(
                            alignment: const Alignment(0, -0.88),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'N',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: const Alignment(0, 0.85),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _navigationTarget!.distanceString,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _miniMapZoom = (_miniMapZoom + 1).clamp(10, 20);
                        });
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _miniMapZoom = (_miniMapZoom - 1).clamp(10, 20);
                        });
                      },
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.remove,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // AR Direction Arrow
        Positioned.fill(
          child: StreamBuilder<CompassEvent>(
            stream: FlutterCompass.events,
            builder: (context, snapshot) {
              double heading = 0;
              if (snapshot.hasData && snapshot.data!.heading != null) {
                heading = snapshot.data!.heading!;
              }

              double targetLat = _navigationTarget!.latitude;
              double targetLng = _navigationTarget!.longitude;

              if (_routePoints.length >= 2) {
                double minDist = double.infinity;
                int closestIndex = 0;
                for (int i = 0; i < _routePoints.length; i++) {
                  final d = Geolocator.distanceBetween(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    _routePoints[i].latitude,
                    _routePoints[i].longitude,
                  );
                  if (d < minDist) {
                    minDist = d;
                    closestIndex = i;
                  }
                }
                final lookAhead = (closestIndex + 8).clamp(
                  0,
                  _routePoints.length - 1,
                );
                targetLat = _routePoints[lookAhead].latitude;
                targetLng = _routePoints[lookAhead].longitude;
              }

              final bearing = _calculateBearing(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                targetLat,
                targetLng,
              );

              final relativeAngle = (bearing - heading) * pi / 180;

              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 100),
                  child: Transform.rotate(
                    angle: relativeAngle,
                    child: CustomPaint(
                      size: const Size(120, 120),
                      painter: _ArrowPainter(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Bottom info card
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                if (_navigationTarget!.photoUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _navigationTarget!.photoUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildNavIcon(),
                    ),
                  )
                else
                  _buildNavIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _navigationTarget!.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD44500).withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _navigationTarget!.typeLabel,
                              style: const TextStyle(
                                color: Color(0xFFD44500),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_navigationTarget!.rating != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${_navigationTarget!.rating}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_walk,
                            color: Colors.green,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _navigationTarget!.distanceString,
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '~${(_navigationTarget!.distanceMeters / 80).round()} min walk',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final url = Uri.parse(
                      'https://www.google.com/maps/dir/?api=1&destination=${_navigationTarget!.latitude},${_navigationTarget!.longitude}&travelmode=walking',
                    );
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD44500),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.directions,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFD44500).withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.place, color: Color(0xFFD44500), size: 28),
    );
  }
}

// ── Bottom Sheet for Explore ──
class _ExploreSheet extends StatefulWidget {
  final List<NearbyPlace> places;
  final bool loading;
  final String selectedCategory;
  final String sortBy;
  final Function(String) onCategoryChanged;
  final Function(String) onSortChanged;
  final Function(NearbyPlace) onPlaceSelected;
  final Function(NearbyPlace) onDirections;
  final _CameraScreenState parentState;

  const _ExploreSheet({
    required this.places,
    required this.loading,
    required this.selectedCategory,
    required this.sortBy,
    required this.onCategoryChanged,
    required this.onSortChanged,
    required this.onPlaceSelected,
    required this.onDirections,
    required this.parentState,
  });

  @override
  State<_ExploreSheet> createState() => _ExploreSheetState();
}

class _ExploreSheetState extends State<_ExploreSheet> {
  late String _category;
  late String _sort;
  List<NearbyPlace> _places = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _sort = widget.sortBy;
    _places = widget.places;
    _loading = widget.loading;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final position =
        await widget.parentState._locationService.getCurrentPosition();
    final places = await widget.parentState._placesService.getNearbyPlaces(
      position.latitude,
      position.longitude,
      radius: 5000,
      category: _category,
    );
    if (_sort == 'nearest') {
      places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    } else {
      places.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    }
    if (mounted) {
      setState(() {
        _places = places;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Explore Nearby',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children:
                      PlacesService.categoryTypes.keys.map((cat) {
                        final isSelected = _category == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _category = cat);
                              widget.onCategoryChanged(cat);
                              _refresh();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? const Color(0xFFD44500)
                                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                cat,
                                style: TextStyle(
                                  color:
                                      isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                  fontSize: 13,
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '${_places.length} places found',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _sort = _sort == 'nearest' ? 'top_rated' : 'nearest';
                        });
                        widget.onSortChanged(_sort);
                        if (_sort == 'nearest') {
                          _places.sort(
                            (a, b) =>
                                a.distanceMeters.compareTo(b.distanceMeters),
                          );
                        } else {
                          _places.sort(
                            (a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0),
                          );
                        }
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sort == 'nearest' ? Icons.near_me : Icons.star,
                              size: 14,
                              color: const Color(0xFFD44500),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sort == 'nearest' ? 'Nearest' : 'Top Rated',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child:
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _places.isEmpty
                        ? const Center(
                          child: Text(
                            'No places found in this category',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                        : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _places.length,
                          itemBuilder: (context, index) {
                            final place = _places[index];
                            return _buildPlaceCard(place);
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceCard(NearbyPlace place) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onPlaceSelected(place),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (place.photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    place.photoUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildIcon(place),
                  ),
                )
              else
                _buildIcon(place),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD44500).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            place.typeLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFD44500),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          place.distanceString,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        if (place.isOpen != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            place.isOpen! ? 'Open' : 'Closed',
                            style: TextStyle(
                              fontSize: 11,
                              color: place.isOpen! ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (place.vicinity != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        place.vicinity!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  if (place.rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        Text(
                          '${place.rating}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => widget.onPlaceSelected(place),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.green,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => widget.onDirections(place),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD44500).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.directions_walk,
                            color: Color(0xFFD44500),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(NearbyPlace place) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFD44500).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        place.types.contains('restaurant') || place.types.contains('food')
            ? Icons.restaurant
            : place.types.contains('cafe')
            ? Icons.coffee
            : place.types.contains('bank')
            ? Icons.account_balance
            : place.types.contains('shopping_mall') ||
                place.types.contains('store')
            ? Icons.store
            : place.types.contains('movie_theater')
            ? Icons.movie
            : Icons.place,
        color: const Color(0xFFD44500),
        size: 28,
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final glowPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, 55, glowPaint);

    final bgPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.4)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 50, bgPaint);

    final borderPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawCircle(center, 50, borderPaint);

    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - 30);
    arrowPath.lineTo(center.dx + 22, center.dy + 10);
    arrowPath.lineTo(center.dx + 12, center.dy + 10);
    arrowPath.lineTo(center.dx + 12, center.dy + 25);
    arrowPath.lineTo(center.dx - 12, center.dy + 25);
    arrowPath.lineTo(center.dx - 12, center.dy + 10);
    arrowPath.lineTo(center.dx - 22, center.dy + 10);
    arrowPath.close();

    final shadowPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.save();
    canvas.translate(2, 2);
    canvas.drawPath(arrowPath, shadowPaint);
    canvas.restore();

    final arrowPaint =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFF90CAF9)],
          ).createShader(Rect.fromCenter(center: center, width: 60, height: 60))
          ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);

    final arrowBorderPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    canvas.drawPath(arrowPath, arrowBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IndoorArrowPainter extends CustomPainter {
  final bool isElevator;
  _IndoorArrowPainter({this.isElevator = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final color = isElevator ? Colors.blue : Colors.green;

    final glowPaint =
        Paint()
          ..color = color.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(center, 45, glowPaint);

    final bgPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 42, bgPaint);

    final borderPaint =
        Paint()
          ..color = color.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
    canvas.drawCircle(center, 42, borderPaint);

    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - 25);
    arrowPath.lineTo(center.dx + 18, center.dy + 5);
    arrowPath.lineTo(center.dx + 10, center.dy + 5);
    arrowPath.lineTo(center.dx + 10, center.dy + 20);
    arrowPath.lineTo(center.dx - 10, center.dy + 20);
    arrowPath.lineTo(center.dx - 10, center.dy + 5);
    arrowPath.lineTo(center.dx - 18, center.dy + 5);
    arrowPath.close();

    final arrowPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, color],
          ).createShader(Rect.fromCenter(center: center, width: 50, height: 50))
          ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);

    final arrowBorderPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    canvas.drawPath(arrowPath, arrowBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _IndoorArrowPainter oldDelegate) =>
      isElevator != oldDelegate.isElevator;
}
