import 'package:flutter/material.dart';
import '../../models/building.dart';

class BuildingDetailScreen extends StatelessWidget {
  final Building building;
  const BuildingDetailScreen({super.key, required this.building});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _getTabCount(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(building.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_border),
              onPressed: () {},
            ),
            IconButton(icon: const Icon(Icons.share), onPressed: () {}),
          ],
          bottom: TabBar(isScrollable: true, tabs: _buildTabs()),
        ),
        body: TabBarView(children: _buildTabViews()),
      ),
    );
  }

  int _getTabCount() {
    int count = 1;
    if (building.faculty.isNotEmpty) count++;
    if (building.rooms.isNotEmpty) count++;
    if (building.notableEvents.isNotEmpty) count++;
    return count;
  }

  List<Tab> _buildTabs() {
    final tabs = <Tab>[const Tab(text: 'Overview')];
    if (building.faculty.isNotEmpty) tabs.add(const Tab(text: 'Faculty'));
    if (building.rooms.isNotEmpty) tabs.add(const Tab(text: 'Rooms'));
    if (building.notableEvents.isNotEmpty) tabs.add(const Tab(text: 'History'));
    return tabs;
  }

  List<Widget> _buildTabViews() {
    final views = <Widget>[_buildOverviewTab()];
    if (building.faculty.isNotEmpty) views.add(_buildFacultyTab());
    if (building.rooms.isNotEmpty) views.add(_buildRoomsTab());
    if (building.notableEvents.isNotEmpty) views.add(_buildHistoryTab());
    return views;
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _getTypeColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              building.type.name.toUpperCase(),
              style: TextStyle(
                color: _getTypeColor(),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (building.description != null)
            Text(
              building.description!,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          const SizedBox(height: 16),
          if (building.constructionYear != null)
            _infoRow(
              Icons.calendar_today,
              'Built',
              '${building.constructionYear}',
            ),
          if (building.architect != null)
            _infoRow(Icons.architecture, 'Architect', building.architect!),
          if (building.architecturalStyle != null)
            _infoRow(Icons.style, 'Style', building.architecturalStyle!),
          if (building.address != null)
            _infoRow(Icons.location_on, 'Address', building.address!),
          if (building.departments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Departments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: building.departments
                  .map(
                    (d) => Chip(
                      label: Text(d, style: const TextStyle(fontSize: 13)),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFacultyTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: building.faculty.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final f = building.faculty[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text(f.name.split(' ').map((n) => n[0]).take(2).join()),
          ),
          title: Text(
            f.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('${f.title ?? ''}\n${f.department ?? ''}'),
          isThreeLine: true,
          trailing: f.officeRoom != null
              ? Chip(
                  label: Text(
                    'Room ${f.officeRoom}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildRoomsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: building.rooms.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final r = building.rooms[index];
        return ListTile(
          leading: Icon(_getRoomIcon(r.type), color: Colors.grey[700]),
          title: Text(r.name ?? 'Room ${r.number}'),
          subtitle: Text('Room ${r.number} • Floor ${r.floor ?? "N/A"}'),
          trailing: r.capacity != null
              ? Text(
                  '${r.capacity} seats',
                  style: const TextStyle(color: Colors.grey),
                )
              : null,
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (building.architecturalStyle != null) ...[
            const Text(
              'Architectural Style',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              building.architecturalStyle!,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
          ],
          const Text(
            'Notable Events',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...building.notableEvents.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFFD44500),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      event,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  IconData _getRoomIcon(String? type) {
    switch (type) {
      case 'auditorium':
        return Icons.event_seat;
      case 'classroom':
        return Icons.class_;
      case 'lab':
        return Icons.science;
      case 'office':
        return Icons.person;
      default:
        return Icons.room;
    }
  }

  Color _getTypeColor() {
    switch (building.type) {
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
}
