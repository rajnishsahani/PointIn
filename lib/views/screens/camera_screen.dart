import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/building.dart';
import '../../services/building_service.dart';
import '../../services/location_service.dart';
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
  Building? _detectedBuilding;
  String? _distance;
  bool _isInitialized = false;

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

  // Pause/resume camera when app goes to background
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

    // Use back camera
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

    // Listen for GPS updates and find nearest building
    _locationService.getPositionStream().listen((position) async {
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
        // Full screen camera preview
        CameraPreview(_controller!),

        // Scan crosshair in center
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

        // Top info bar
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
                  _detectedBuilding != null
                      ? Icons.location_on
                      : Icons.gps_fixed,
                  color:
                      _detectedBuilding != null
                          ? const Color(0xFFD44500)
                          : Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _detectedBuilding != null
                      ? 'Building detected nearby!'
                      : 'Point at a building...',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),

        // AR overlay card when building is detected
        if (_detectedBuilding != null)
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
                    // Building type icon
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
                    // Building info
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
                          const SizedBox(height: 2),
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
                    // Distance badge
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _distance ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFFD44500),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
