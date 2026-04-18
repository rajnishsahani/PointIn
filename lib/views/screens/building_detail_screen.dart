import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/building.dart';
import '../../services/local_storage_service.dart';
import '../../services/wikipedia_service.dart';
import '../../services/places_service.dart';
import 'home_screen.dart';

class BuildingDetailScreen extends StatefulWidget {
  final Building building;
  const BuildingDetailScreen({super.key, required this.building});

  @override
  State<BuildingDetailScreen> createState() => _BuildingDetailScreenState();
}

class _BuildingDetailScreenState extends State<BuildingDetailScreen>
    with SingleTickerProviderStateMixin {
  final LocalStorageService _storage = LocalStorageService();
  final WikipediaService _wikipedia = WikipediaService();
  bool _isBookmarked = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  String? _wikiSummary;
  String? _wikiImageUrl;
  String? _wikiPageUrl;
  bool _wikiLoading = false;

  String? _placesImageUrl;
  final PlacesService _placesService = PlacesService(
    apiKey: 'AIzaSyD3LT18vanu6-6ONyTjQHql9fRocSCFR-c',
  );

  @override
  void initState() {
    super.initState();
    _checkBookmark();
    _loadWikipediaData();
    _loadPlacesPhoto();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkBookmark() async {
    final result = await _storage.isBookmarked(widget.building.id);
    setState(() => _isBookmarked = result);
  }

  Future<void> _loadWikipediaData() async {
    setState(() => _wikiLoading = true);
    var data = await _wikipedia.getBuildingSummary(
      '${widget.building.name} Syracuse University',
    );
    if (data['summary'] == null) {
      data = await _wikipedia.getBuildingSummary(widget.building.name);
    }
    if (mounted) {
      setState(() {
        _wikiSummary = data['summary'];
        _wikiImageUrl = data['imageUrl'];
        _wikiPageUrl = data['pageUrl'];
        _wikiLoading = false;
      });
    }
  }

  Future<void> _loadPlacesPhoto() async {
    final photoUrl = await _placesService.getBuildingPhoto(
      widget.building.name,
      widget.building.latitude,
      widget.building.longitude,
    );
    if (mounted && photoUrl != null) {
      setState(() {
        _placesImageUrl = photoUrl;
      });
    }
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarked) {
      await _storage.removeBookmark(widget.building.id);
    } else {
      await _storage.addBookmark(widget.building.id);
    }
    setState(() => _isBookmarked = !_isBookmarked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isBookmarked ? 'Bookmarked!' : 'Bookmark removed'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openDirections() async {
    final building = widget.building;
    Navigator.of(context).popUntil((route) => route.isFirst);
    homeScreenKey.currentState?.navigateToCameraWithTarget(building);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _getTabCount(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.building.name),
          actions: [
            IconButton(
              icon: Icon(
                _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: _isBookmarked ? const Color(0xFFD44500) : null,
              ),
              onPressed: _toggleBookmark,
            ),
            IconButton(icon: const Icon(Icons.share), onPressed: () {}),
          ],
          bottom: TabBar(isScrollable: true, tabs: _buildTabs()),
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: TabBarView(children: _buildTabViews()),
        ),
      ),
    );
  }

  int _getTabCount() {
    int count = 1;
    if (widget.building.faculty.isNotEmpty) count++;
    if (widget.building.rooms.isNotEmpty) count++;
    count++;
    return count;
  }

  List<Tab> _buildTabs() {
    final tabs = <Tab>[const Tab(text: 'Overview')];
    if (widget.building.faculty.isNotEmpty)
      tabs.add(const Tab(text: 'Faculty'));
    if (widget.building.rooms.isNotEmpty) tabs.add(const Tab(text: 'Rooms'));
    tabs.add(const Tab(text: 'History'));
    return tabs;
  }

  List<Widget> _buildTabViews() {
    final views = <Widget>[_buildOverviewTab()];
    if (widget.building.faculty.isNotEmpty) views.add(_buildFacultyTab());
    if (widget.building.rooms.isNotEmpty) views.add(_buildRoomsTab());
    views.add(_buildHistoryTab());
    return views;
  }

  Widget _buildDirectionsButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openDirections,
        icon: const Icon(Icons.directions_walk, color: Colors.white),
        label: const Text(
          'Get Directions',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD44500),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > 600;

        if (isLandscape) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_placesImageUrl != null || _wikiImageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _placesImageUrl ?? _wikiImageUrl!,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getTypeColor().withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.building.type.name.toUpperCase(),
                              style: TextStyle(
                                color: _getTypeColor(),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (widget.building.description != null)
                            Text(
                              widget.building.description!,
                              style: const TextStyle(fontSize: 16, height: 1.5),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.building.constructionYear != null)
                            _infoRow(
                              Icons.calendar_today,
                              'Built',
                              '${widget.building.constructionYear}',
                            ),
                          if (widget.building.architect != null)
                            _infoRow(
                              Icons.architecture,
                              'Architect',
                              widget.building.architect!,
                            ),
                          if (widget.building.architecturalStyle != null)
                            _infoRow(
                              Icons.style,
                              'Style',
                              widget.building.architecturalStyle!,
                            ),
                          if (widget.building.address != null)
                            _infoRow(
                              Icons.location_on,
                              'Address',
                              widget.building.address!,
                            ),
                          if (widget.building.departments.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Departments',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  widget.building.departments
                                      .map(
                                        (d) => Chip(
                                          label: Text(
                                            d,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDirectionsButton(),
              ],
            ),
          );
        }

        // Portrait: single column
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_placesImageUrl != null || _wikiImageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _placesImageUrl ?? _wikiImageUrl!,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if (_placesImageUrl != null || _wikiImageUrl != null)
                const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getTypeColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.building.type.name.toUpperCase(),
                  style: TextStyle(
                    color: _getTypeColor(),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.building.description != null)
                Text(
                  widget.building.description!,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              const SizedBox(height: 16),
              if (widget.building.constructionYear != null)
                _infoRow(
                  Icons.calendar_today,
                  'Built',
                  '${widget.building.constructionYear}',
                ),
              if (widget.building.architect != null)
                _infoRow(
                  Icons.architecture,
                  'Architect',
                  widget.building.architect!,
                ),
              if (widget.building.architecturalStyle != null)
                _infoRow(
                  Icons.style,
                  'Style',
                  widget.building.architecturalStyle!,
                ),
              if (widget.building.address != null)
                _infoRow(
                  Icons.location_on,
                  'Address',
                  widget.building.address!,
                ),
              if (widget.building.departments.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Departments',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      widget.building.departments
                          .map(
                            (d) => Chip(
                              label: Text(
                                d,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
              const SizedBox(height: 24),
              _buildDirectionsButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFacultyTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: widget.building.faculty.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final f = widget.building.faculty[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFD44500).withOpacity(0.1),
            child: Text(
              f.name.split(' ').map((n) => n[0]).take(2).join(),
              style: const TextStyle(
                color: Color(0xFFD44500),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            f.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text('${f.title ?? ''}\n${f.department ?? ''}'),
          isThreeLine: true,
          trailing:
              f.officeRoom != null
                  ? Chip(
                    label: Text(
                      'Room ${f.officeRoom}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                  : null,
          onTap: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder:
                  (context) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (f.title != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            f.title!,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                        if (f.department != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            f.department!,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (f.email != null && f.email!.isNotEmpty)
                          ListTile(
                            leading: const Icon(
                              Icons.email,
                              color: Color(0xFFD44500),
                            ),
                            title: Text(f.email!),
                            subtitle: const Text('Send email'),
                            onTap: () async {
                              final url = Uri.parse('mailto:${f.email}');
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url);
                              }
                              Navigator.pop(context);
                            },
                          ),
                        if (f.phone != null && f.phone!.isNotEmpty)
                          ListTile(
                            leading: const Icon(
                              Icons.phone,
                              color: Colors.green,
                            ),
                            title: Text(f.phone!),
                            subtitle: const Text('Call'),
                            onTap: () async {
                              final url = Uri.parse('tel:${f.phone}');
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url);
                              }
                              Navigator.pop(context);
                            },
                          ),
                        if (f.officeRoom != null)
                          ListTile(
                            leading: const Icon(Icons.room, color: Colors.blue),
                            title: Text('Office: ${f.officeRoom}'),
                            subtitle: const Text('Room location'),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
            );
          },
        );
      },
    );
  }

  Widget _buildRoomsTab() {
    return Column(
      children: [
        if (widget.building.reserveRoomUrl != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final url = Uri.parse(widget.building.reserveRoomUrl!);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.event_available, color: Colors.white),
                label: const Text(
                  'Reserve a Study Room',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: widget.building.rooms.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final r = widget.building.rooms[index];
              return ListTile(
                leading: Icon(_getRoomIcon(r.type), color: Colors.grey[700]),
                title: Text(r.name ?? 'Room ${r.number}'),
                subtitle: Text('Room ${r.number} • Floor ${r.floor ?? "N/A"}'),
                trailing:
                    r.capacity != null
                        ? Text(
                          '${r.capacity} seats',
                          style: const TextStyle(color: Colors.grey),
                        )
                        : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.building.architecturalStyle != null) ...[
            const Text(
              'Architectural Style',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.building.architecturalStyle!,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
          ],
          if (widget.building.notableEvents.isNotEmpty) ...[
            const Text(
              'Notable Events',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...widget.building.notableEvents.map(
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
            const SizedBox(height: 20),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.language, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'From Wikipedia',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_wikiLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_wikiSummary != null) ...[
                  Text(
                    _wikiSummary!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                  ),
                  if (_wikiPageUrl != null) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final url = Uri.parse(_wikiPageUrl!);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: const Text(
                        'Read more on Wikipedia →',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ] else
                  const Text(
                    'No Wikipedia article found for this building.',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
              ],
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
    switch (widget.building.type) {
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
