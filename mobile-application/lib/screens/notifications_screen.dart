import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = ApiService.getNotifications();
  }

  void _refresh() {
    setState(() {
      _notificationsFuture = ApiService.getNotifications();
    });
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return "Recent";
    try {
      final dt = DateTime.parse(createdAt.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) {
        return "${diff.inMinutes} mins ago";
      } else if (diff.inHours < 24) {
        return "${diff.inHours} hours ago";
      } else {
        return "${diff.inDays} days ago";
      }
    } catch (_) {
      return "Recent";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Notifications",
          style: TextStyle(
            color: Color(0xFF1A237E),
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2962FF)));
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 14),
                  const Text(
                    "No notifications yet",
                    style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            color: const Color(0xFF2962FF),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final item = notifications[index];
                final id = item['id'];
                final title = item['title'] ?? 'Notice';
                final desc = item['description'] ?? '';
                final isRead = item['is_read'] == true;
                final type = item['type'] ?? 'info';
                final time = _formatTime(item['created_at']);

                IconData icon = Icons.notifications_rounded;
                Color iconColor = const Color(0xFF2962FF);

                if (type == 'submission') {
                  icon = Icons.description_outlined;
                  iconColor = Colors.blue;
                } else if (type == 'status_update') {
                  icon = Icons.wb_sunny_outlined;
                  iconColor = Colors.orange;
                } else if (title.contains("Resolved")) {
                  icon = Icons.check_circle_rounded;
                  iconColor = Colors.green;
                } else if (title.contains("Points")) {
                  icon = Icons.stars_rounded;
                  iconColor = Colors.amber;
                }

                return GestureDetector(
                  onTap: () {
                    if (id != null && !isRead) {
                      ApiService.markNotificationRead(id is int ? id : int.parse(id.toString()));
                      setState(() {
                        item['is_read'] = true;
                      });
                    }
                  },
                  child: _buildNotificationCard(
                    title: title,
                    description: desc,
                    time: time,
                    icon: icon,
                    iconColor: iconColor,
                    isNew: !isRead,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard({
    required String title,
    required String description,
    required String time,
    required IconData icon,
    required Color iconColor,
    bool isNew = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                    if (isNew)
                      const Icon(Icons.circle, color: Colors.green, size: 8),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}