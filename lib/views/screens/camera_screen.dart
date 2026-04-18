import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
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
  String _sortBy = 'nearest'; // 'nearest' or 'top_rated'

  // AR navigation state
  NearbyPlace? _navigationTarget;
  Position? _currentPosition;
  GoogleMapController? _miniMapController;
  List<LatLng> _routePoints = [];
  double _miniMapZoom = 16;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startLocationUpdates();
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
    // Add this — get initial position immediately
    final pos = await _locationService.getCurrentPosition();
    _currentPosition = pos;

    // Auto-start navigation if a building target was passed
    if (widget.navigationTarget != null) {
      _startBuildingNavigation();
    }

    _locationService.getPositionStream().listen((position) async {
      _currentPosition = position;
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

    // Convert Building to NearbyPlace so the AR navigation works
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

    // Fetch walking route
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

              // Fetch real walking route
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

        // Crosshair
        if (_navigationTarget == null)
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white38, width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(
                  Icons.center_focus_strong,
                  color: Colors.white38,
                  size: 40,
                ),
              ),
            ),
          ),

        // AR Navigation arrow
        if (_navigationTarget != null && _currentPosition != null)
          _buildNavigationOverlay(),

        // Top bar
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
                  _navigationTarget != null
                      ? Icons.navigation
                      : _detectedBuilding != null
                      ? Icons.location_on
                      : Icons.gps_fixed,
                  color:
                      _navigationTarget != null
                          ? Colors.green
                          : _detectedBuilding != null
                          ? const Color(0xFFD44500)
                          : Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _navigationTarget != null
                        ? 'Navigating to ${_navigationTarget!.name}'
                        : _detectedBuilding != null
                        ? 'Building detected nearby!'
                        : 'Point at a building...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_navigationTarget != null)
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
                          Icon(Icons.explore, color: Colors.white, size: 14),
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
          ),
        ),

        // Building detection card
        if (_detectedBuilding != null && _navigationTarget == null)
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

  Widget _buildNavigationOverlay() {
    // Set initial zoom based on distance
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

                  // Update mini-map rotation in real time
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
                          // Live Google Map
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

                          // Edge fade overlay
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

                          // N indicator
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

                          // Distance badge
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

              // Zoom +/- buttons
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

        // AR Direction Arrow (Google Street View style)
        Positioned.fill(
          child: StreamBuilder<CompassEvent>(
            stream: FlutterCompass.events,
            builder: (context, snapshot) {
              double heading = 0;
              if (snapshot.hasData && snapshot.data!.heading != null) {
                heading = snapshot.data!.heading!;
              }

              // Find the next point along the route to guide turn-by-turn
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
    if (mounted)
      setState(() {
        _places = places;
        _loading = false;
      });
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
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Explore Nearby',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),

              // Category chips
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

              // Sort toggle
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

              // Places list
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
              // Photo
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
              // Info
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
              // Rating + actions
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
                      // Navigate via camera
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
                      // Google Maps directions
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

    // Outer glow
    final glowPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, 55, glowPaint);

    // Semi-transparent circle background
    final bgPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.4)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 50, bgPaint);

    // Circle border
    final borderPaint =
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawCircle(center, 50, borderPaint);

    // Arrow pointing UP (forward direction)
    final arrowPath = Path();
    arrowPath.moveTo(center.dx, center.dy - 30); // tip
    arrowPath.lineTo(center.dx + 22, center.dy + 10); // right
    arrowPath.lineTo(center.dx + 12, center.dy + 10);
    arrowPath.lineTo(center.dx + 12, center.dy + 25); // right leg bottom
    arrowPath.lineTo(center.dx - 12, center.dy + 25); // left leg bottom
    arrowPath.lineTo(center.dx - 12, center.dy + 10);
    arrowPath.lineTo(center.dx - 22, center.dy + 10); // left
    arrowPath.close();

    // Arrow shadow
    final shadowPaint =
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.save();
    canvas.translate(2, 2);
    canvas.drawPath(arrowPath, shadowPaint);
    canvas.restore();

    // Arrow fill gradient
    final arrowPaint =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFF90CAF9)],
          ).createShader(Rect.fromCenter(center: center, width: 60, height: 60))
          ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);

    // Arrow border
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
