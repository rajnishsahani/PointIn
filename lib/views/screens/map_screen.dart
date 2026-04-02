import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../blocs/building/building_bloc.dart';
import '../../models/building.dart';
import '../../services/location_service.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import 'building_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Building? _selectedBuilding;
  Position? _currentPosition;
  final LocationService _locationService = LocationService();
  Building? _nearestBuilding;
  String? _nearestDistance;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final hasPermission = await _locationService.requestPermission();
    if (!hasPermission) return;

    // Get initial position
    final position = await _locationService.getCurrentPosition();
    setState(() => _currentPosition = position);

    // Move camera to user location
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
    );

    // Listen for position updates
    _locationService.getPositionStream().listen((position) {
      setState(() => _currentPosition = position);
      _updateNearestBuilding(position);
    });
  }

  // Find which building is closest to the user
  void _updateNearestBuilding(Position position) {
    final state = context.read<BuildingBloc>().state;
    if (state is! BuildingsLoaded) return;

    Building? nearest;
    double minDist = double.infinity;

    for (final building in state.buildings) {
      final dist = Helpers.calculateDistance(
        position.latitude,
        position.longitude,
        building.latitude,
        building.longitude,
      );
      if (dist < minDist) {
        minDist = dist;
        nearest = building;
      }
    }

    if (nearest != null && minDist < AppConstants.buildingDetectionRadius) {
      setState(() {
        _nearestBuilding = nearest;
        _nearestDistance = Helpers.formatDistance(minDist);
      });
    } else {
      setState(() {
        _nearestBuilding = null;
        _nearestDistance = null;
      });
    }
  }

  Set<Marker> _buildMarkers(List<Building> buildings) {
    return buildings.map((building) {
      return Marker(
        markerId: MarkerId(building.id),
        position: LatLng(building.latitude, building.longitude),
        infoWindow: InfoWindow(title: building.name),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          building.type == BuildingType.commercial
              ? BitmapDescriptor.hueBlue
              : BitmapDescriptor.hueOrange,
        ),
        onTap: () {
          setState(() => _selectedBuilding = building);
        },
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BuildingBloc, BuildingState>(
      builder: (context, state) {
        if (state is BuildingLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is BuildingError) {
          return Center(child: Text('Error: ${state.message}'));
        }

        if (state is BuildingsLoaded) {
          return Stack(
            children: [
              // Google Map
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target:
                      _currentPosition != null
                          ? LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          )
                          : const LatLng(
                            AppConstants.suCenterLat,
                            AppConstants.suCenterLng,
                          ),
                  zoom: AppConstants.defaultZoom,
                ),
                markers: _buildMarkers(state.filteredBuildings),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                onMapCreated: (controller) => _mapController = controller,
                onTap: (_) => setState(() => _selectedBuilding = null),
              ),

              // Nearest building banner at top
              if (_nearestBuilding != null)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => BuildingDetailScreen(
                                building: _nearestBuilding!,
                              ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD44500),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.near_me,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_nearestBuilding!.name} — $_nearestDistance away',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                ),

              // Building preview card when pin is tapped
              if (_selectedBuilding != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => BuildingDetailScreen(
                                building: _selectedBuilding!,
                              ),
                        ),
                      );
                    },
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _getTypeColor(
                                  _selectedBuilding!.type,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _getTypeIcon(_selectedBuilding!.type),
                                color: _getTypeColor(_selectedBuilding!.type),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedBuilding!.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedBuilding!.description ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (_currentPosition != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      Helpers.formatDistance(
                                        Helpers.calculateDistance(
                                          _currentPosition!.latitude,
                                          _currentPosition!.longitude,
                                          _selectedBuilding!.latitude,
                                          _selectedBuilding!.longitude,
                                        ),
                                      ),
                                      style: const TextStyle(
                                        color: Color(0xFFD44500),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Color _getTypeColor(BuildingType type) {
    switch (type) {
      case BuildingType.university:
        return const Color(0xFFD44500);
      case BuildingType.commercial:
        return Colors.blue;
      case BuildingType.historical:
        return Colors.brown;
      case BuildingType.mixed:
        return Colors.purple;
    }
  }

  IconData _getTypeIcon(BuildingType type) {
    switch (type) {
      case BuildingType.university:
        return Icons.school;
      case BuildingType.commercial:
        return Icons.store;
      case BuildingType.historical:
        return Icons.museum;
      case BuildingType.mixed:
        return Icons.business;
    }
  }
}
