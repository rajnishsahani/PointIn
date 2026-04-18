import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/building/building_bloc.dart';
import '../../models/building.dart';
import 'map_screen.dart';
import 'camera_screen.dart';
import 'search_screen.dart';
import 'bookmarks_screen.dart';

// Global key so any screen can access HomeScreenState
final GlobalKey<HomeScreenState> homeScreenKey = GlobalKey<HomeScreenState>();

class HomeScreen extends StatefulWidget {
  HomeScreen() : super(key: homeScreenKey);

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Building? _navigationTarget;

  List<Widget> get _screens => [
    const MapScreen(),
    CameraScreen(navigationTarget: _navigationTarget),
    const SearchScreen(),
  ];

  void navigateToCameraWithTarget(Building building) {
    setState(() {
      _navigationTarget = building;
      _currentIndex = 1;
    });
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return BlocBuilder<BuildingBloc, BuildingState>(
          builder: (context, state) {
            final activeFilter =
                state is BuildingsLoaded ? state.activeFilter : null;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter Buildings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _filterOption(context, 'All Buildings', null, activeFilter),
                  _filterOption(
                    context,
                    'University',
                    BuildingType.university,
                    activeFilter,
                  ),
                  _filterOption(
                    context,
                    'Commercial',
                    BuildingType.commercial,
                    activeFilter,
                  ),
                  _filterOption(
                    context,
                    'Mixed Use',
                    BuildingType.mixed,
                    activeFilter,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _filterOption(
    BuildContext context,
    String label,
    BuildingType? type,
    BuildingType? activeFilter,
  ) {
    final isSelected = activeFilter == type;
    return ListTile(
      leading: Icon(
        _getTypeIcon(type),
        color: isSelected ? const Color(0xFFD44500) : Colors.grey,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? const Color(0xFFD44500) : null,
        ),
      ),
      trailing:
          isSelected ? const Icon(Icons.check, color: Color(0xFFD44500)) : null,
      onTap: () {
        context.read<BuildingBloc>().add(FilterByType(type));
        Navigator.pop(context);
      },
    );
  }

  IconData _getTypeIcon(BuildingType? type) {
    switch (type) {
      case BuildingType.university:
        return Icons.school;
      case BuildingType.commercial:
        return Icons.store;
      case BuildingType.mixed:
        return Icons.business;
      case BuildingType.historical:
        return Icons.museum;
      case null:
        return Icons.all_inclusive;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PointIn'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookmarksScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _screens[_currentIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            activeIcon: Icon(Icons.camera_alt),
            label: 'Camera',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}
