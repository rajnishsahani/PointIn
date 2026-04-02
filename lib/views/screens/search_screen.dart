import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/search/search_bloc.dart';
import '../../blocs/building/building_bloc.dart';
import '../../models/building.dart';
import 'building_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            onChanged: (query) {
              context.read<SearchBloc>().add(SearchQueryChanged(query));
            },
            decoration: InputDecoration(
              hintText: 'Search buildings, faculty, rooms...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        context.read<SearchBloc>().add(ClearSearch());
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
        ),

        // Results
        Expanded(
          child: BlocBuilder<SearchBloc, SearchState>(
            builder: (context, state) {
              // Default view — show all buildings
              if (state is SearchInitial) {
                return _buildAllBuildings();
              }
              // No results
              if (state is SearchEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No results for "${state.query}"',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }
              // Search results
              if (state is SearchResults) {
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (state.buildings.isNotEmpty) ...[
                      Text(
                        'Buildings (${state.buildings.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...state.buildings.map(
                        (b) => _buildBuildingTile(context, b),
                      ),
                    ],
                    if (state.faculty.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Faculty (${state.faculty.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...state.faculty.map((f) => _buildFacultyTile(f)),
                    ],
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAllBuildings() {
    return BlocBuilder<BuildingBloc, BuildingState>(
      builder: (context, state) {
        if (state is BuildingsLoaded) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.buildings.length,
            itemBuilder: (context, index) {
              return _buildBuildingTile(context, state.buildings[index]);
            },
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildBuildingTile(BuildContext context, Building building) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(building.type).withOpacity(0.1),
          child: Icon(
            _getTypeIcon(building.type),
            color: _getTypeColor(building.type),
          ),
        ),
        title: Text(
          building.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          building.campusRegion ?? building.address ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BuildingDetailScreen(building: building),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFacultyTile(Faculty faculty) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(faculty.name.split(' ').map((n) => n[0]).take(2).join()),
        ),
        title: Text(faculty.name),
        subtitle: Text(faculty.title ?? faculty.department ?? ''),
        trailing: faculty.email != null
            ? const Icon(Icons.email_outlined, color: Colors.grey)
            : null,
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
