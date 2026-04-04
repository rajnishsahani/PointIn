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

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

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

  Future<void> _loadNearbyPlaces() async {
    setState(() => _placesLoading = true);

    final position = await _locationService.getCurrentPosition();
    final places = await _placesService.getNearbyPlaces(
      position.latitude,
      position.longitude,
      radius: 3200,
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
            onPlaceSelected: (place) {
              Navigator.pop(context);
              setState(() => _navigationTarget = place);
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
                    onTap: () => setState(() => _navigationTarget = null),
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
    final bearing = _calculateBearing(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _navigationTarget!.latitude,
      _navigationTarget!.longitude,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Direction arrow
        Transform.rotate(
          angle: bearing * pi / 180,
          child: const Icon(Icons.navigation, color: Colors.green, size: 80),
        ),
        const SizedBox(height: 16),
        // Distance + name card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                _navigationTarget!.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _navigationTarget!.distanceString,
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _navigationTarget!.typeLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final url = Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${_navigationTarget!.latitude},${_navigationTarget!.longitude}&travelmode=walking',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD44500),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Open in Google Maps',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
      radius: 3200,
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
