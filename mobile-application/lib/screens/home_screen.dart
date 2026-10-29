import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;

import '../services/api_service.dart';
import 'report_issue_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';
import 'notifications_screen.dart';
import 'my_reports_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  String userName = "Citizen";
  String userLocation = "Mumbai";

  int _reportedCount = 0;
  int _resolvedCount = 0;
  int _userPoints = 0;
  List<Map<String, dynamic>> _allComplaints = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {

    // 1. Load user profile
    final user = await ApiService.getUser();
    if (user != null) {
      setState(() {
        userName = user['name'] ?? 'Citizen';
        userLocation = user['location'] ?? 'Mumbai';
      });
    }

    // Refresh profile in background
    ApiService.getProfile().then((fresh) {
      if (fresh != null && mounted) {
        setState(() {
          userName = fresh['name'] ?? userName;
          userLocation = fresh['location'] ?? userLocation;
        });
      }
    });

    // 2. Load stats & points
    final rewardsData = await ApiService.getRewardsStats();
    final stats = rewardsData['stats'] as Map<String, dynamic>? ?? {};

    // 3. Load all complaints for map & stats
    final complaints = await ApiService.getComplaints();

    if (!mounted) return;
    setState(() {
      _allComplaints = complaints;
      _reportedCount = stats['reported'] ?? complaints.length;
      _resolvedCount = stats['resolved'] ?? complaints.where((c) => c['status'] == 'Resolved' || c['status'] == 'RESOLVED' || c['status'] == 'CLOSED').length;
      _userPoints = stats['points'] ?? 0;
    });
  }

  Future<void> _navigateToReport() async {
    setState(() => _selectedIndex = 1);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ReportIssueScreen()),
    );

    if (result == 'return_home' || result == null) {
      setState(() => _selectedIndex = 0);
      _loadDashboardData();
    }
  }

  void _showPointsDialog(int livePoints) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Your Civic Points ⭐"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "$livePoints Points",
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2962FF),
              ),
            ),
            const SizedBox(height: 20),
            _pointsRow("Pending report", "+10"),
            _pointsRow("Photo + GPS bonus", "+10"),
            _pointsRow("Resolved report", "+25"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Awesome"),
          ),
        ],
      ),
    );
  }

  Widget _pointsRow(String title, String pointsValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Text(
            pointsValue,
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2962FF).withValues(alpha: 0.03),
              ),
            ),
          ),
          _buildCurrentScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF2962FF),
          unselectedItemColor: Colors.grey.shade400,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          elevation: 0,
          onTap: (index) {
            if (index == 1) {
              _navigateToReport();
            } else {
              setState(() => _selectedIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.grid_view_rounded), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.add_circle_rounded), label: 'Report'),
            BottomNavigationBarItem(
                icon: Icon(Icons.stars_rounded), label: 'Rewards'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeContent();
      case 2:
        return const RewardsScreen();
      case 3:
        return ProfileScreen(
          currentName: userName,
          currentLocation: userLocation,
          onSave: (newName, newLoc) async {
            setState(() {
              userName = newName;
              userLocation = newLoc;
            });
            await ApiService.updateProfile(name: newName, location: newLoc);
          },
          onBackToHome: () => setState(() => _selectedIndex = 0),
        );
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: const Color(0xFF2962FF),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2962FF).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded,
                                color: Color(0xFF2962FF), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              userLocation,
                              style: const TextStyle(
                                color: Color(0xFF2962FF),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Hello, $userName 👋",
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A237E),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border:
                                Border.all(color: Colors.grey.shade200, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                              )
                            ],
                          ),
                          child: const Icon(Icons.notifications_none_rounded,
                              color: Color(0xFF1A237E), size: 26),
                        ),
                        Positioned(
                          right: 12,
                          top: 10,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              _buildLiveStats(),

              const SizedBox(height: 35),

              const Text(
                "Quick Actions",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: _navigateToReport,
                child: _buildActionCard(
                  "Report an Issue",
                  "Fast report civic problems with GPS",
                  Icons.add_business_rounded,
                  Colors.redAccent,
                ),
              ),

              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MyReportsScreen(),
                    ),
                  ).then((_) => _loadDashboardData());
                },
                child: _buildActionCard(
                  "My Reports",
                  "Track your submission status in PostgreSQL",
                  Icons.analytics_rounded,
                  const Color(0xFF2962FF),
                ),
              ),

              GestureDetector(
                onTap: () => setState(() => _selectedIndex = 2),
                child: _buildActionCard(
                  "Civic Rewards",
                  "Redeem your points for badges",
                  Icons.workspace_premium_rounded,
                  Colors.amber.shade700,
                ),
              ),

              const SizedBox(height: 30),

              const Text(
                "Nearby Issues Map",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 16),

              _buildMapPreview(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveStats() {
    return Row(
      children: [
        _buildStatCard(
          _reportedCount.toString(),
          "Reported",
          Icons.edit_document,
          const Color(0xFF2962FF),
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          _resolvedCount.toString(),
          "Resolved",
          Icons.check_circle_rounded,
          Colors.green,
        ),
        const SizedBox(width: 10),
        _buildStatCard(
          _userPoints.toString(),
          "Points",
          Icons.stars_rounded,
          Colors.orange,
          onTap: () => _showPointsDialog(_userPoints),
        ),
      ],
    );
  }

  Widget _buildMapPreview() {
    final List<Marker> markers = [];

    for (var complaint in _allComplaints) {
      final lat = complaint['latitude'];
      final lng = complaint['longitude'];
      final status = complaint['status'] ?? 'Pending';

      if (lat != null && lng != null) {
        Color markerColor = Colors.orange;
        if (status == 'In Progress' || status == 'IN_PROGRESS' || status == 'VERIFIED' || status == 'ASSIGNED') {
          markerColor = const Color(0xFF2962FF);
        } else if (status == 'Resolved' || status == 'RESOLVED' || status == 'CLOSED') {
          markerColor = Colors.green;
        }

        final double latVal = (lat is num) ? lat.toDouble() : double.tryParse(lat.toString()) ?? 0;
        final double lngVal = (lng is num) ? lng.toDouble() : double.tryParse(lng.toString()) ?? 0;

        if (latVal != 0 && lngVal != 0) {
          markers.add(
            Marker(
              point: latlng.LatLng(latVal, lngVal),
              width: 40,
              height: 40,
              child: Icon(
                Icons.location_on,
                color: markerColor,
                size: 36,
              ),
            ),
          );
        }
      }
    }

    final center = markers.isNotEmpty
        ? markers.first.point
        : const latlng.LatLng(13.0827, 80.2707);

    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.cvk',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              bottom: 14,
              left: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map_rounded, color: Color(0xFF2962FF), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        markers.isEmpty
                            ? "No location-based reports yet"
                            : "${markers.length} live issues mapped from PostgreSQL",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color themeColor, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 118,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: themeColor.withValues(alpha: 0.06),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: themeColor, size: 26),
              const SizedBox(height: 8),
              FittedBox(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
      String title, String subtitle, IconData icon, Color iconBg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconBg.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: iconBg),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          color: Colors.grey.shade300,
          size: 16,
        ),
      ),
    );
  }
}