import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'language_screen.dart';

class OtpScreen extends StatefulWidget {
  final bool isFromMobile;
  final String verificationId;
  final String? phoneNumber;
  final String? citizenName;

  const OtpScreen({
    super.key,
    required this.isFromMobile,
    required this.verificationId,
    this.phoneNumber,
    this.citizenName,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  String? _otpError;
  late String _currentVerificationId;

  // Resend cooldown timer (60s)
  int _resendCooldown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentVerificationId = widget.verificationId;
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    setState(() => _resendCooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      setState(() {
        _otpError = "Please enter the complete 6-digit OTP";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _otpError = null;
    });

    try {
      final res = await ApiService.verifyOtp(
        verificationId: _currentVerificationId,
        otp: otp,
        name: widget.citizenName,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res['success'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LanguageScreen()),
        );
      } else {
        setState(() {
          _otpError = res['message'] ?? "Invalid OTP code. Please try again.";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _otpError = "Verification error: $e";
      });
    }
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0 || widget.phoneNumber == null) return;

    setState(() {
      _isLoading = true;
      _otpError = null;
    });

    final res = await ApiService.sendOtp(widget.phoneNumber!);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      _currentVerificationId = res['verificationId'] ?? _currentVerificationId;
      _startCooldownTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("A new OTP code has been sent.")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? "Could not resend OTP.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = _otpError != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF1A237E),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: _buildCircle(200, const Color(0xFFE3F2FD)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  Container(
                    height: 90,
                    width: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2962FF).withValues(alpha: 0.1),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      hasError
                          ? Icons.error_outline_rounded
                          : Icons.shield_outlined,
                      size: 45,
                      color: hasError ? Colors.red : const Color(0xFF2962FF),
                    ),
                  ),
                  const SizedBox(height: 35),
                  const Text(
                    "Verify Code",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      widget.phoneNumber != null
                          ? "Enter the 6-digit code sent to ${widget.phoneNumber}"
                          : "Enter the 6-digit code sent to your mobile number",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      onChanged: (_) {
                        if (_otpError != null) {
                          setState(() => _otpError = null);
                        }
                      },
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 16.0,
                        color: hasError ? Colors.red : const Color(0xFF2962FF),
                      ),
                      decoration: InputDecoration(
                        counterText: "",
                        errorText: _otpError,
                        hintText: "••••••",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade300,
                          letterSpacing: 16,
                        ),
                        filled: true,
                        fillColor: hasError
                            ? Colors.red.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 20),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: hasError ? Colors.red : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color:
                                hasError ? Colors.red : const Color(0xFF2962FF),
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide:
                              const BorderSide(color: Colors.red, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 35),
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
                      onPressed: _isLoading ? null : _verifyOtp,
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
                              "Verify & Continue",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Didn't receive the code? ",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      GestureDetector(
                        onTap: _resendCooldown == 0 ? _resendCode : null,
                        child: Text(
                          _resendCooldown > 0
                              ? "Resend in ${_resendCooldown}s"
                              : "Resend Code",
                          style: TextStyle(
                            color: _resendCooldown > 0
                                ? Colors.grey
                                : const Color(0xFF2962FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
}
