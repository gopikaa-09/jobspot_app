import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:jobspot_app/core/theme/app_theme.dart';
import 'package:jobspot_app/core/theme/map_styles.dart';
import 'package:jobspot_app/core/utils/map_clustering_helper.dart';
import 'package:jobspot_app/core/utils/global_refresh_manager.dart';
import 'package:jobspot_app/features/jobs/presentation/job_details_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:jobspot_app/features/dashboard/presentation/providers/seeker_home_provider.dart';

class JobItem implements ClusterItem {
  final Map<String, dynamic> job;
  final LatLng jobLocation;

  JobItem(this.job, this.jobLocation);

  @override
  LatLng get location => jobLocation;
}

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  GoogleMapController? _mapController;

  // State
  Set<Marker> _markers = {};
  List<JobItem> _jobItems = [];
  bool _isLoading = true;
  double _currentZoom = 10.0;
  String? _selectedJobId;
  final CameraPosition _initialPosition = CameraPosition(
    target: LatLng(19.0760, 72.8777),
    zoom: 10,
  );
  Position? _userPosition;
  double _lastClusterZoom = 10;

  List<Map<String, dynamic>>? _lastJobs;

  final Map<String, BitmapDescriptor> _iconCache = {};

  final TextEditingController _searchController = TextEditingController();
  final List<String> _selectedJobTypes = [];
  final List<String> _jobTypes = [
    'Full-Time',
    'Part-Time',
    'Contract',
    'Internship',
    'Freelance',
  ];

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWithProvider();
  }

  void _syncWithProvider() {
    final provider = Provider.of<SeekerHomeProvider>(context);
    if (provider.recommendedJobs != _lastJobs) {
      _lastJobs = provider.recommendedJobs;
      _updateJobItemsFromProvider(provider.recommendedJobs);
    }
  }

  void _updateJobItemsFromProvider(List<Map<String, dynamic>> jobs) {
    final items = jobs
        .where((j) => j['latitude'] != null && j['longitude'] != null)
        .map((j) => JobItem(j, LatLng(j['latitude'], j['longitude'])))
        .toList();

    setState(() {
      _jobItems = items;
      _isLoading = false;
    });
    _updateFilteredItems();
  }

  Future<void> _initMap() async {
    await _loadMarkerIcons();
    _initLocation();
  }

  Future<void> _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      _getCurrentLocation();
    }
  }

  Future<void> _loadMarkerIcons() async {
    _iconCache['unselected_small'] = await _getBitmapDescriptor(
      'assets/icons/map_icon_2.png',
      32,
    ); // Resize to 32
    _iconCache['unselected_medium'] = await _getBitmapDescriptor(
      'assets/icons/map_icon_2.png',
      48,
    ); // Resize to 48
    _iconCache['unselected_large'] = await _getBitmapDescriptor(
      'assets/icons/map_icon_2.png',
      64,
    ); // Resize to 64

    // Selected
    _iconCache['selected_small'] = await _getBitmapDescriptor(
      'assets/icons/map_icon_1.png',
      40,
    );
    _iconCache['selected_medium'] = await _getBitmapDescriptor(
      'assets/icons/map_icon_1.png',
      56,
    );
    _iconCache['selected_large'] = await _getBitmapDescriptor(
      'assets/icons/map_icon_1.png',
      72,
    );

    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _getBitmapDescriptor(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    ui.FrameInfo fi = await codec.getNextFrame();
    final bytes = (await fi.image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    return BitmapDescriptor.bytes(bytes);
  }

  void _updateFilteredItems() {
    List<JobItem> filtered = _jobItems;
    final query = _searchController.text.toLowerCase();

    // Search Filter
    if (query.isNotEmpty) {
      filtered = filtered.where((item) {
        final title = (item.job['title'] as String?)?.toLowerCase() ?? '';
        final company =
            (item.job['company_name'] as String?)?.toLowerCase() ?? '';
        return title.contains(query) || company.contains(query);
      }).toList();
    }

    // Type Filter
    if (_selectedJobTypes.isNotEmpty) {
      filtered = filtered.where((item) {
        final type =
            (item.job['job_type'] as String?) ??
            (item.job['work_mode'] as String?) ??
            '';
        return _selectedJobTypes.any(
          (selected) => type.toLowerCase().contains(selected.toLowerCase()),
        );
      }).toList();
    }

    _clusterItems(filtered);
  }

  int _clusterRequestId = 0;

  Future<void> _clusterItems(List<JobItem> items) async {
    final requestId = ++_clusterRequestId;

    final clusters = MapClusterer.cluster(items, _currentZoom);
    final markers = <Marker>{};

    for (final cluster in clusters) {
      markers.add(await _buildMarker(cluster));
    }

    if (!mounted || requestId != _clusterRequestId) return;

    setState(() {
      _markers = markers;
    });
  }

  // Cluster icon cache
  final Map<int, BitmapDescriptor> _clusterIconCache = {};

  Future<Marker> _buildMarker(MapCluster<JobItem> cluster) async {
    if (cluster.isMultiple) {
      final count = cluster.count;
      BitmapDescriptor icon;

      if (_clusterIconCache.containsKey(count)) {
        icon = _clusterIconCache[count]!;
      } else {
        icon = await _getClusterBitmap(count, size: 30, text: count.toString());
        _clusterIconCache[count] = icon;
      }

      if (_clusterIconCache.length > 50) {
        _clusterIconCache.clear();
      }

      return Marker(
        markerId: MarkerId(cluster.getId()),
        position: cluster.location,
        onTap: () {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(cluster.location, _currentZoom + 2),
          );
        },
        icon: icon,
      );
    } else {
      final item = cluster.items.first;
      final jobId = item.job['id'].toString();
      final isSelected = jobId == _selectedJobId;

      // Dynamic sizing logic based on _currentZoom
      String sizeKey = 'medium';
      if (_currentZoom < 11) {
        sizeKey = 'small';
      } else if (_currentZoom > 15) {
        sizeKey = 'large';
      }

      final iconKey = '${isSelected ? "selected" : "unselected"}_$sizeKey';
      final icon = _iconCache[iconKey] ?? BitmapDescriptor.defaultMarker;

      return Marker(
        markerId: MarkerId(jobId),
        position: cluster.location,
        icon: icon,
        zIndexInt: isSelected ? 10 : 1,
        onTap: () {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(cluster.location, 16),
          ); // Zoom in on tap
          setState(() {
            _selectedJobId = jobId;
          });
          _showJobDetails(item.job);
        },
      );
    }
  }

  Future<BitmapDescriptor> _getClusterBitmap(
    int count, {
    int size = 150,
    String? text,
  }) async {
    if (kIsWeb) return BitmapDescriptor.defaultMarker;

    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint1 = Paint()..color = AppColors.darkPurple;
    final Paint paint2 = Paint()
      ..color = Colors.white; // Keep white for high contrast on map pins

    canvas.drawCircle(Offset(size / 2, size / 2), size / 2.0, paint1);
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2.2, paint2);
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2.8, paint1);

    if (text != null) {
      TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
      painter.text = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size / 3,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      );
      painter.layout();
      painter.paint(
        canvas,
        Offset(size / 2 - painter.width / 2, size / 2 - painter.height / 2),
      );
    }

    final img = await pictureRecorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.bytes(data!.buffer.asUint8List());
  }

  void _showJobDetails(Map<String, dynamic> job) {
    final provider = Provider.of<SeekerHomeProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.35,
          minChildSize: 0.2,
          maxChildSize: 0.6,
          expand: false,
          builder: (_, controller) {
            final isApplied = provider.isJobApplied(job['id']);
            return JobDetailsSheet(
              job: job,
              scrollController: controller,
              isApplied: isApplied,
              userPosition: _userPosition,
            );
          },
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() {
          _selectedJobId = null;
          _updateFilteredItems();
        });
      }
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _getCurrentLocation() async {
    try {
      _userPosition = await Geolocator.getCurrentPosition();
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_userPosition!.latitude, _userPosition!.longitude),
          14,
        ),
      );
    } catch (e) {
      // Handle error or permission denied silently or via snackbar
    }
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter by Job Type',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ..._jobTypes.map((type) {
                    return CheckboxListTile(
                      title: Text(type),
                      value: _selectedJobTypes.contains(type),
                      onChanged: (bool? value) {
                        setModalState(() {
                          if (value == true) {
                            _selectedJobTypes.add(type);
                          } else {
                            _selectedJobTypes.remove(type);
                          }
                        });
                        // Update main state
                        setState(() {
                          _updateFilteredItems();
                        });
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: _initialPosition,
            markers: _markers,
            style: Theme.of(context).brightness == Brightness.dark
                ? MapStyles.darkStyle
                : null,
            myLocationButtonEnabled: false,
            myLocationEnabled: true,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            onCameraMove: (position) {
              _currentZoom = position.zoom;
            },
            onCameraIdle: () {
              if ((_currentZoom - _lastClusterZoom).abs() > 0.3) {
                _lastClusterZoom = _currentZoom;
                _updateFilteredItems();
              }
            },
            onTap: (_) {
              if (_selectedJobId != null) {
                setState(() {
                  _selectedJobId = null;
                  _updateFilteredItems();
                });
              }
            },
          ),
          if (_isLoading ||
              context.select<SeekerHomeProvider, bool>((p) => p.isLoading))
            const Center(child: CircularProgressIndicator()),

          // Search/Filter UI
          Padding(
            padding: const EdgeInsets.only(
              top: 48,
              right: 16,
              left: 16,
            ), // Increased top padding for safe area
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() {
                      _updateFilteredItems();
                    }),
                    decoration: InputDecoration(
                      fillColor: Theme.of(context).colorScheme.surface,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'Search position, company...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ActionChip(
                        onPressed: _showFilterOptions,
                        avatar: const Icon(Icons.filter_list, size: 18),
                        label: const Text('Filter Type'),
                        backgroundColor: Theme.of(context).cardColor,
                        // elevation: 2, // Removed elevation to fix lint
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              heroTag: 'map_refresh_fab',
              backgroundColor: Theme.of(context).colorScheme.surface,
              onPressed: () => GlobalRefreshManager.refreshAll(context),
              tooltip: 'Refresh Jobs',
              child: const Icon(Icons.refresh, color: AppColors.purple),
            ),
          ),
          Positioned(
            bottom: 24,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              heroTag: 'map_location_fab',
              backgroundColor: Theme.of(context).colorScheme.surface,
              onPressed: _getCurrentLocation,
              child: const Icon(Icons.my_location, color: AppColors.purple),
            ),
          ),
        ],
      ),
    );
  }
}

class JobDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> job;
  final ScrollController scrollController;
  final bool isApplied;
  final Position? userPosition;

  const JobDetailsSheet({
    super.key,
    required this.job,
    required this.scrollController,
    this.isApplied = false,
    this.userPosition,
  });

  String _calculateDistance() {
    if (userPosition == null) return '';
    final lat = job['latitude'];
    final lng = job['longitude'];
    if (lat == null || lng == null) return '';

    final distanceInMeters = Geolocator.distanceBetween(
      userPosition!.latitude,
      userPosition!.longitude,
      lat,
      lng,
    );
    return '${(distanceInMeters / 1000).toStringAsFixed(1)} km away';
  }

  Future<void> _openDirections() async {
    final lat = job['latitude'];
    final lng = job['longitude'];
    if (lat != null && lng != null) {
      final uri = Uri.parse("google.navigation:q=$lat,$lng");
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback to web map
        final webUri = Uri.parse(
          "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng",
        );
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final minPay = job['pay_amount_min'] ?? 0;
    final maxPay = job['pay_amount_max'];
    final salaryStr = maxPay != null ? '₹$minPay - ₹$maxPay' : '₹$minPay';
    final companyName = job['company_name'] ?? 'Unknown Company';
    final distance = _calculateDistance();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.1,
            ), // Shadow is fine as black
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    size: 32,
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job['title'] ?? 'Job Position',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        companyName,
                        style: textTheme.bodyMedium?.copyWith(
                          color: textTheme.bodyMedium?.color?.withValues(
                            alpha: 0.7,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              job['location'] ?? 'Remote',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildChip(
                    context,
                    label: job['work_mode']?.toString().toUpperCase() ?? '',
                    icon: Icons.work_outline,
                    color: AppColors.purple,
                  ),
                  const SizedBox(width: 8),
                  _buildChip(
                    context,
                    label: salaryStr,
                    icon: Icons.attach_money,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildChip(
                    context,
                    label: distance,
                    icon: Icons.directions,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openDirections,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.directions_outlined),
                    label: Text(
                      'Directions',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => JobDetailsScreen(
                            job: job,
                            userRole: 'seeker',
                            isApplied: isApplied,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkPurple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isApplied ? 'Applied' : 'View Details',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
