import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  late Future<Map<String, dynamic>> _rewardsFuture;

  @override
  void initState() {
    super.initState();
    _rewardsFuture = ApiService.getRewardsStats();
  }

  void _refresh() {
    setState(() {
      _rewardsFuture = ApiService.getRewardsStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Rewards & Points",
          style: TextStyle(
            color: Color(0xFF1A237E),
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black87, size: 20),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            }
          },
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _rewardsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2962FF)));
          }

          final data = snapshot.data ?? {};
          final rawStats = data['stats'] as Map<String, dynamic>? ?? {};
          final history = data['history'] as List<dynamic>? ?? [];

          final Map<String, int> stats = {
            'reported': (rawStats['reported'] is num) ? (rawStats['reported'] as num).toInt() : 0,
            'pending': (rawStats['pending'] is num) ? (rawStats['pending'] as num).toInt() : 0,
            'inProgress': (rawStats['inProgress'] is num) ? (rawStats['inProgress'] as num).toInt() : 0,
            'resolved': (rawStats['resolved'] is num) ? (rawStats['resolved'] as num).toInt() : 0,
            'points': (rawStats['points'] is num) ? (rawStats['points'] as num).toInt() : 0,
            'geoReports': (rawStats['geoReports'] is num) ? (rawStats['geoReports'] as num).toInt() : 0,
            'photoReports': (rawStats['photoReports'] is num) ? (rawStats['photoReports'] as num).toInt() : 0,
          };

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            color: const Color(0xFF2962FF),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildMainPointsCard(stats),
                  const SizedBox(height: 30),

                  const Text(
                    "Badges & Achievements",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBadgeGrid(stats),

                  const SizedBox(height: 30),
                  const Text(
                    "Recent Point Activity",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRecentActivityList(history),

                  const SizedBox(height: 25),
                  _buildEarnPointsGuide(),

                  const SizedBox(height: 30),
                  const Text(
                    "Demo City Leaderboard",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLeaderboard(stats['points'] ?? 0),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainPointsCard(Map<String, int> stats) {
    final points = stats['points'] ?? 0;
    final reported = stats['reported'] ?? 0;
    final resolved = stats['resolved'] ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color.fromARGB(255, 22, 63, 168), Color.fromARGB(255, 22, 63, 168)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B2FF7).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white24,
            child: Icon(Icons.stars_rounded, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 12),
          Text(
            points.toString(),
            style: const TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const Text(
            "Total Civic Impact Points",
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(reported.toString(), "Issues\nReported"),
              _statItem(resolved.toString(), "Issues\nResolved"),
              _statItem(_levelName(points), "Impact\nLevel"),
            ],
          ),
        ],
      ),
    );
  }

  String _levelName(int points) {
    if (points >= 1000) return "Elite";
    if (points >= 500) return "Hero";
    if (points >= 250) return "Active";
    if (points >= 100) return "Rising";
    return "Starter";
  }

  Widget _statItem(String val, String label) {
    return Column(
      children: [
        Text(
          val,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildBadgeGrid(Map<String, int> stats) {
    final reported = stats['reported'] ?? 0;
    final resolved = stats['resolved'] ?? 0;
    final points = stats['points'] ?? 0;
    final geo = stats['geoReports'] ?? 0;
    final photo = stats['photoReports'] ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 0.84,
      children: [
        _badgeCard("First Reporter", "Submit your first issue", Icons.flag,
            Colors.orange, reported >= 1, reported / 1),
        _badgeCard("Civic Starter", "Report 5+ civic issues", Icons.rocket_launch,
            Colors.blue, reported >= 5, reported / 5),
        _badgeCard("Civic Hero", "Resolve 5+ issues", Icons.shield,
            Colors.green, resolved >= 5, resolved / 5),
        _badgeCard("City Guardian", "Resolve 10+ issues", Icons.domain,
            Colors.purple, resolved >= 10, resolved / 10),
        _badgeCard("Geo Accurate", "Add GPS in 5 reports", Icons.location_on,
            Colors.redAccent, geo >= 5, geo / 5),
        _badgeCard("Evidence Expert", "Add photo proof 5 times",
            Icons.camera_alt, Colors.teal, photo >= 5, photo / 5),
        _badgeCard("Point Collector", "Earn 250+ points", Icons.stars,
            Colors.amber, points >= 250, points / 250),
        _badgeCard("Change Maker", "Earn 1000+ points", Icons.emoji_events,
            Colors.deepPurple, points >= 1000, points / 1000),
      ],
    );
  }

  Widget _badgeCard(String title, String desc, IconData icon, Color color,
      bool earned, double progress) {
    final safeProgress = progress.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: earned ? color.withValues(alpha: 0.5) : Colors.transparent),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: earned ? color : Colors.grey.shade300, size: 38),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(desc,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
          const SizedBox(height: 12),
          if (earned)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 14),
                SizedBox(width: 4),
                Text("Unlocked",
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            )
          else
            Column(
              children: [
                LinearProgressIndicator(
                  value: safeProgress,
                  backgroundColor: Colors.grey.shade100,
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(height: 4),
                Text("${(safeProgress * 100).toInt()}% complete",
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityList(List<dynamic> history) {
    if (history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          "No point activity yet. Submit your first report with GPS to begin earning points!",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final recentItems = history.take(5).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        children: recentItems.map((item) {
          final Map<String, dynamic> record = item is Map<String, dynamic> ? item : {};
          final reason = record['reason'] ?? 'Community Contribution';
          final points = record['points'] ?? 10;

          return _activityTile(reason.toString(), "Civic Connect Impact", "+$points");
        }).toList(),
      ),
    );
  }

  Widget _activityTile(String title, String subtitle, String points) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.green.withValues(alpha: 0.1),
        child: const Icon(Icons.add, color: Colors.green, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: Text(points,
          style: const TextStyle(
              color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildEarnPointsGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("How Points Are Calculated",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
          const SizedBox(height: 12),
          _guideRow(Icons.add_circle_outline, "Pending report: +10 points"),
          _guideRow(Icons.location_on_outlined, "GPS location attached: +5 points"),
          _guideRow(Icons.camera_alt_outlined, "Photo proof attached: +5 points"),
          _guideRow(Icons.check_circle_outline, "Issue resolved by authority: +25 points"),
        ],
      ),
    );
  }

  Widget _guideRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: Colors.blue.shade900)),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(int myPoints) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _leaderboardTile(1, "Ananya R", "1250 points", false),
          _leaderboardTile(2, "Rahul S", "980 points", false),
          _leaderboardTile(3, "Meera K", "720 points", false),
          _leaderboardTile(4, "You", "$myPoints points", true),
        ],
      ),
    );
  }

  Widget _leaderboardTile(int rank, String name, String pts, bool isMe) {
    return Container(
      color: isMe ? Colors.green.withValues(alpha: 0.05) : Colors.transparent,
      child: ListTile(
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: isMe ? Colors.green : Colors.grey.shade100,
          child: Text(rank.toString(),
              style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(name,
            style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
        subtitle: const Text("Local Civic Contributor",
            style: TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pts, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Icon(Icons.emoji_events,
                color: rank == 1 ? Colors.amber : Colors.grey.shade300,
                size: 18),
          ],
        ),
      ),
    );
  }
}