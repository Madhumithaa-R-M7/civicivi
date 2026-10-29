import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isMobileSelected = true;
  bool _isLoading = false;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final input = _inputController.text.trim();
    final password = _passwordController.text.trim();

    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isMobileSelected ? "Please enter your mobile number" : "Please enter your email"),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please enter your password"),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String identifier = input;
      if (isMobileSelected && identifier.length == 10 && !identifier.startsWith('+')) {
        identifier = "+91$identifier";
      }

      final res = await ApiService.login(identifier: identifier, password: password);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res['success'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? "Invalid email/phone or password"),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Login error: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: _buildCircle(250, const Color(0xFFE3F2FD)),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: IconButton(
                  icon: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF2962FF), size: 28),
                  tooltip: 'Backend Server Settings',
                  onPressed: _showServerConfigSheet,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  Center(
                    child: Container(
                      height: 90,
                      width: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2962FF).withValues(alpha: 0.15),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_city_rounded,
                        size: 50,
                        color: Color(0xFF2962FF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    "Welcome Back",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A237E),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Log in to your Civic Connect account to keep your neighborhood better.",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    height: 55,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        _buildEnhancedTab(
                          "Mobile",
                          Icons.phone_android_rounded,
                          isMobileSelected,
                          () => setState(() {
                            isMobileSelected = true;
                            _inputController.clear();
                          }),
                        ),
                        _buildEnhancedTab(
                          "Email",
                          Icons.email_rounded,
                          !isMobileSelected,
                          () => setState(() {
                            isMobileSelected = false;
                            _inputController.clear();
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    isMobileSelected ? "Mobile Number" : "Email Address",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _inputController,
                    keyboardType: isMobileSelected
                        ? TextInputType.phone
                        : TextInputType.emailAddress,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: isMobileSelected
                          ? "Enter your mobile number"
                          : "Enter your email",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: isMobileSelected
                          ? Container(
                              width: 60,
                              alignment: Alignment.center,
                              child: const Text(
                                "+91",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.alternate_email_rounded,
                              color: Color(0xFF2962FF),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 16,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF2962FF),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Password",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: "Enter your password",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.normal,
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFF2962FF),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 16,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF2962FF),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(
                          color: Color(0xFF2962FF),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2962FF).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2962FF),
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              "Sign In",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: RichText(
                        text: TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 15,
                          ),
                          children: const [
                            TextSpan(
                              text: "Create One",
                              style: TextStyle(
                                color: Color(0xFF2962FF),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildEnhancedTab(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? const Color(0xFF2962FF)
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isSelected
                      ? const Color(0xFF1A237E)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerConfigSheet() {
    final controller = TextEditingController(text: ApiService.baseUrl);
    bool isTesting = false;
    String? statusMessage;
    bool? isSuccess;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2962FF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.dns_rounded, color: Color(0xFF2962FF)),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Backend Server Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select or enter the URL where the CivicConnect backend is hosted:',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPresetChip('🌐 Render Cloud', ApiService.renderUrl, controller, setSheetState),
                      _buildPresetChip('🔌 USB Cable (ADB)', ApiService.usbUrl, controller, setSheetState),
                      _buildPresetChip('📶 Wi-Fi LAN', ApiService.lanUrl, controller, setSheetState),
                      _buildPresetChip('💻 Emulator', ApiService.emulatorUrl, controller, setSheetState),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Server Base URL',
                      hintText: 'https://your-service.onrender.com',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                  ),
                  if (statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          isSuccess == true ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: isSuccess == true ? Colors.green : Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusMessage!,
                            style: TextStyle(
                              color: isSuccess == true ? Colors.green.shade800 : Colors.red.shade800,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isTesting
                              ? null
                              : () async {
                                  setSheetState(() {
                                    isTesting = true;
                                    statusMessage = 'Connecting...';
                                    isSuccess = null;
                                  });
                                  final ok = await ApiService.testConnection(controller.text.trim());
                                  setSheetState(() {
                                    isTesting = false;
                                    isSuccess = ok;
                                    statusMessage = ok
                                        ? 'Connected! Backend is reachable.'
                                        : 'Connection failed. Check URL or network.';
                                  });
                                },
                          icon: isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering_rounded),
                          label: const Text('Test Connection'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final newUrl = controller.text.trim();
                            if (newUrl.isNotEmpty) {
                              await ApiService.setCustomBaseUrl(newUrl);
                              if (context.mounted) {
                                Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Server URL set to: $newUrl'),
                                    backgroundColor: const Color(0xFF2962FF),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Apply'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2962FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPresetChip(
    String label,
    String url,
    TextEditingController controller,
    StateSetter setSheetState,
  ) {
    final isSelected = controller.text == url;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) {
        setSheetState(() {
          controller.text = url;
        });
      },
    );
  }
}