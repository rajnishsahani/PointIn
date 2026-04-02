import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../blocs/building/building_bloc.dart';
import '../../models/building.dart';
import '../../utils/constants.dart';
import 'building_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Building? _selectedBuilding;

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
                initialCameraPosition: const CameraPosition(
                  target: LatLng(
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

              // Building preview card at bottom when pin is tapped
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
                                color: const Color(0xFFD44500).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.school,
                                color: Color(0xFFD44500),
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
}
