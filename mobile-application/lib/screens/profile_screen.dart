import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'language_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentLocation;
  final Function(String, String) onSave;
  final VoidCallback onBackToHome;

  const ProfileScreen({
    super.key,
    required this.currentName,
    required this.currentLocation,
    required this.onSave,
    required this.onBackToHome,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isEditing = false;
  late TextEditingController nameController;
  late TextEditingController locationController;
  String phoneNumber = "91******63";

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    locationController = TextEditingController(text: widget.currentLocation);
    _loadStoredUser();
  }

  Future<void> _loadStoredUser() async {
    final user = await ApiService.getUser();
    if (user != null && mounted) {
      final rawPhone = user['phone'] ?? '';
      if (rawPhone.toString().isNotEmpty) {
        final p = rawPhone.toString();
        if (p.length >= 8) {
          setState(() {
            phoneNumber = "${p.substring(0, 3)}****${p.substring(p.length - 2)}";
          });
        }
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    locationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
          onPressed: widget.onBackToHome,
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 30),
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 15),
              child: Text(
                "Account Preferences & Settings",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D3142),
                ),
              ),
            ),
            _buildMenuTile(
              Icons.chat_bubble_outline_rounded,
              "Language",
              Colors.pinkAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LanguageScreen()),
                );
              },
            ),
            _buildMenuTile(Icons.image_search_rounded, "My Media & Uploads", Colors.purpleAccent),
            _buildMenuTile(
              Icons.notifications_active_outlined,
              "Notifications",
              Colors.orangeAccent,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
              },
            ),
            _buildMenuTile(Icons.favorite_border_rounded, "Support Civic Connect", Colors.redAccent),
            _buildMenuTile(Icons.security_rounded, "Privacy & Safety", Colors.blueAccent),
            const SizedBox(height: 30),
            _buildLogoutButton(),
            const SizedBox(height: 10),
            const Center(child: Text("v1.0.0 (PostgreSQL Edition)", style: TextStyle(color: Colors.grey, fontSize: 12))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _handleLogout,
        icon: const Icon(Icons.logout_rounded, color: Colors.white),
        label: const Text(
          "LOG OUT",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: isEditing
          ? Column(
              children: [
                _buildCuteTextField(nameController, "Your Name"),
                const SizedBox(height: 12),
                _buildCuteTextField(locationController, "Where do you live?"),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => isEditing = false),
                        child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          widget.onSave(nameController.text, locationController.text);
                          setState(() => isEditing = false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text("Save", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE0E7FF), width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 40,
                        backgroundColor: Color(0xFFF0F4FF),
                        child: Icon(Icons.face_retouching_natural_rounded, size: 40, color: Color(0xFF6366F1)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        height: 28,
                        width: 28,
                        decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.currentName,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF2D3142)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            widget.currentLocation,
                            style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone_iphone_rounded, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            phoneNumber,
                            style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => setState(() => isEditing = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            "Edit Info",
                            style: TextStyle(color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCuteTextField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, Color color, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D3142),
            fontSize: 15,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0B0B0)),
        onTap: onTap,
      ),
    );
  }
}