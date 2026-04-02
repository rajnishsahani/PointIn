import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/building/building_bloc.dart';
import '../../models/building.dart';
import 'building_detail_screen.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

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
              // Map placeholder — will be replaced with Google Maps
              Container(
                color: const Color(0xFFE8E8E8),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Google Maps will appear here',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Add API key to enable',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              // Building list overlay at bottom
              DraggableScrollableSheet(
                initialChildSize: 0.35,
                minChildSize: 0.1,
                maxChildSize: 0.85,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 10),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Drag handle
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                'Nearby Buildings (${state.filteredBuildings.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: state.filteredBuildings.length,
                            itemBuilder: (context, index) {
                              final building = state.filteredBuildings[index];
                              return _BuildingListCard(building: building);
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

// Building card shown in the list
class _BuildingListCard extends StatelessWidget {
  final Building building;
  const _BuildingListCard({required this.building});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BuildingDetailScreen(building: building),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Building type icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor(building.type).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getTypeIcon(building.type),
                  color: _getTypeColor(building.type),
                ),
              ),
              const SizedBox(width: 12),
              // Building info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      building.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      building.description ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
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
