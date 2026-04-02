import 'package:flutter/material.dart';
import '../../models/building.dart';
import '../../services/building_service.dart';
import '../../services/local_storage_service.dart';
import 'building_detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final LocalStorageService _storage = LocalStorageService();
  final BuildingService _buildingService = BuildingService();
  List<Building> _bookmarkedBuildings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final ids = await _storage.getAllBookmarkIds();
    final allBuildings = await _buildingService.getAllBuildings();
    final bookmarked = allBuildings.where((b) => ids.contains(b.id)).toList();
    setState(() {
      _bookmarkedBuildings = bookmarked;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _bookmarkedBuildings.isEmpty
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No bookmarks yet',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tap the bookmark icon on any building',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _bookmarkedBuildings.length,
                itemBuilder: (context, index) {
                  final b = _bookmarkedBuildings[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(
                          0xFFD44500,
                        ).withOpacity(0.1),
                        child: const Icon(
                          Icons.school,
                          color: Color(0xFFD44500),
                        ),
                      ),
                      title: Text(
                        b.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(b.campusRegion ?? b.address ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BuildingDetailScreen(building: b),
                          ),
                        );
                        _loadBookmarks(); // refresh in case bookmark was removed
                      },
                    ),
                  );
                },
              ),
    );
  }
}
