import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchReports(String status) async {
    return await ApiService.getComplaints(status: status, onlyMine: true);
  }

  String _formatDate(dynamic dateRaw) {
    if (dateRaw == null) return "Recently";
    try {
      final dt = DateTime.parse(dateRaw.toString()).toLocal();
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return "$hour:$minute • ${dt.day} ${months[dt.month - 1]} ${dt.year}";
    } catch (_) {
      return dateRaw.toString();
    }
  }

  void _showReportDetailsModal(Map<String, dynamic> data) {
    final String? imageUrl = data['image_url'];
    final String fullImageUrl = (imageUrl != null && imageUrl.isNotEmpty)
        ? (imageUrl.startsWith('http') ? imageUrl : '${ApiService.baseUrl}$imageUrl')
        : '';
    final double? lat = data['latitude'] != null ? double.tryParse(data['latitude'].toString()) : null;
    final double? lng = data['longitude'] != null ? double.tryParse(data['longitude'].toString()) : null;
    final double? accuracy = data['location_accuracy'] != null ? double.tryParse(data['location_accuracy'].toString()) : null;
    final String status = data['status'] ?? 'Pending';
    final String category = data['category'] ?? 'General';
    final String description = data['description'] ?? 'No description provided';
    final String location = data['location'] ?? 'Location not specified';
    final String dateStr = _formatDate(data['created_at']);
    final String? notes = data['resolution_notes'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Complaint #${data['id']}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo Preview
                    if (fullImageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          fullImageUrl,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 120,
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
                            ),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 200,
                              color: Colors.grey.shade100,
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          },
                        ),
                      )
                    else
                      Container(
                        height: 100,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Icon(Icons.image_not_supported_rounded, color: Colors.grey, size: 36),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Status and Category Badges
                    Row(
                      children: [
                        _buildStatusBadge(status),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2962FF).withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(color: Color(0xFF2962FF), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Description
                    const Text("Description", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF1E293B), height: 1.4),
                    ),
                    const SizedBox(height: 16),

                    // Location Details
                    const Text("Recorded Location", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
                          ),
                        ),
                      ],
                    ),

                    if (lat != null && lng != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Coordinates: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}",
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            if (accuracy != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                "GPS Accuracy: ±${accuracy.toStringAsFixed(1)} meters",
                                style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Interactive Map Preview
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(lat, lng),
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.civicconnect.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(lat, lng),
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 38),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Timestamp
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          "Submitted: $dateStr",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    const Text(
                      "Status Timeline & Lifecycle",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    _buildHistoryTimeline(data['id']),

                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.task_alt_rounded, size: 16, color: Colors.green),
                                SizedBox(width: 6),
                                Text(
                                  "Resolution Notes",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(notes, style: TextStyle(fontSize: 12, color: Colors.green.shade900)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Algorithm 13 & 18: Render visual vertical timeline of FSM status transitions
  Widget _buildHistoryTimeline(dynamic rawId) {
    final complaintId = rawId is int ? rawId : (int.tryParse(rawId.toString()) ?? 0);
    if (complaintId <= 0) return const SizedBox.shrink();

    return FutureBuilder<Map<String, dynamic>>(
      future: ApiService.getComplaintHistory(complaintId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2962FF))),
                SizedBox(width: 10),
                Text("Loading lifecycle history...", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }

        final historyList = (snapshot.data != null && snapshot.data!['history'] != null)
            ? (snapshot.data!['history'] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];

        if (historyList.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Text("Initial report submitted. Pending verification.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(historyList.length, (index) {
              final item = historyList[index];
              final isLast = index == historyList.length - 1;
              final toStatus = (item['to_status'] ?? '').toString();
              final date = _formatDate(item['created_at']);
              final actor = item['changed_by_name'] ?? item['changed_by_role'] ?? 'System';
              final reason = item['reason'];

              Color nodeColor = const Color(0xFF2962FF);
              IconData nodeIcon = Icons.radio_button_checked_rounded;

              if (toStatus == 'SUBMITTED') {
                nodeColor = Colors.orange;
                nodeIcon = Icons.hourglass_empty_rounded;
              } else if (toStatus == 'VERIFIED') {
                nodeColor = Colors.indigo;
                nodeIcon = Icons.verified_rounded;
              } else if (toStatus == 'ASSIGNED') {
                nodeColor = Colors.deepPurple;
                nodeIcon = Icons.assignment_ind_rounded;
              } else if (toStatus == 'IN_PROGRESS') {
                nodeColor = const Color(0xFF2962FF);
                nodeIcon = Icons.construction_rounded;
              } else if (toStatus == 'RESOLVED') {
                nodeColor = Colors.green;
                nodeIcon = Icons.check_circle_rounded;
              } else if (toStatus == 'CLOSED') {
                nodeColor = Colors.teal;
                nodeIcon = Icons.task_alt_rounded;
              } else if (toStatus == 'REJECTED') {
                nodeColor = Colors.red;
                nodeIcon = Icons.cancel_rounded;
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: nodeColor.withAlpha(25),
                            shape: BoxShape.circle,
                            border: Border.all(color: nodeColor, width: 1.5),
                          ),
                          child: Icon(nodeIcon, size: 13, color: nodeColor),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: Colors.grey.shade300,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  toStatus,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: nodeColor),
                                ),
                                Text(date, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "By: $actor",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                            ),
                            if (reason != null && reason.toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                reason.toString(),
                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case "Pending":
      case "SUBMITTED":
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty_rounded;
        break;
      case "In Progress":
      case "IN_PROGRESS":
      case "VERIFIED":
      case "ASSIGNED":
        statusColor = const Color(0xFF2962FF);
        statusIcon = Icons.settings_suggest_rounded;
        break;
      case "Resolved":
      case "RESOLVED":
      case "CLOSED":
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case "Rejected":
      case "REJECTED":
        statusColor = Colors.red;
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 13),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A237E), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "My Reports",
          style: TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2962FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2962FF),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "In Progress"),
            Tab(text: "Resolved"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReportList("Pending"),
          _buildReportList("In Progress"),
          _buildReportList("Resolved"),
        ],
      ),
    );
  }

  Widget _buildReportList(String status) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchReports(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF2962FF)));
        }

        final reports = snapshot.data ?? [];

        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_rounded, size: 55, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  "No $status reports found",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          color: const Color(0xFF2962FF),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final data = reports[index];
              return _buildReportCard(data);
            },
          ),
        );
      },
    );
  }

  Widget _buildReportCard(Map<String, dynamic> data) {
    final String? imageUrl = data['image_url'];
    final String fullImageUrl = (imageUrl != null && imageUrl.isNotEmpty)
        ? (imageUrl.startsWith('http') ? imageUrl : '${ApiService.baseUrl}$imageUrl')
        : '';
    final String dateStr = _formatDate(data['created_at']);
    final String category = data['category'] ?? "General";
    final String description = data['description'] ?? "Civic Issue";
    final String status = data['status'] ?? "Pending";
    final String location = data['location'] ?? "";
    final double? lat = data['latitude'] != null ? double.tryParse(data['latitude'].toString()) : null;
    final double? lng = data['longitude'] != null ? double.tryParse(data['longitude'].toString()) : null;

    return GestureDetector(
      onTap: () => _showReportDetailsModal(data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: fullImageUrl.isNotEmpty
                    ? Image.network(
                        fullImageUrl,
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 76,
                          height: 76,
                          color: const Color(0xFFF1F5F9),
                          child: const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 26),
                        ),
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 76,
                            height: 76,
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          );
                        },
                      )
                    : Container(
                        width: 76,
                        height: 76,
                        color: const Color(0xFFF1F5F9),
                        child: const Icon(Icons.image_outlined, color: Colors.grey, size: 28),
                      ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatusBadge(status),
                        Text(
                          "#${data['id']}",
                          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 12, color: Colors.grey),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (lat != null && lng != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.gps_fixed_rounded, size: 11, color: Colors.green),
                          const SizedBox(width: 3),
                          Text(
                            "${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}",
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          category,
                          style: const TextStyle(color: Color(0xFF2962FF), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          dateStr,
                          style: const TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}