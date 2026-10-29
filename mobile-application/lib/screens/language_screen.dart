import 'package:flutter/material.dart';
import 'home_screen.dart'; 

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  // Track the selected language (Operations Kept Original)
  String selectedLanguage = 'English';

  final List<Map<String, String>> languages = [
    {'name': 'English', 'native': 'English'},
    {'name': 'Hindi', 'native': 'हिंदी'},
    {'name': 'Tamil', 'native': 'தமிழ்'},
    {'name': 'Telugu', 'native': 'తెలుగు'},
    {'name': 'Malayalam', 'native': 'മലയാളം'},
    {'name': 'Kannada', 'native': 'ಕನ್ನಡ'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Enhanced Background Gradient
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FBFF), Color(0xFFD9EFFF)],
              ),
            ),
          ),
          
          // Decorative background element (Matches Login/OTP screens)
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2962FF).withValues(alpha: 0.05),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                
                // 2. Premium Header Icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2962FF).withValues(alpha: 0.15),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.translate_rounded, 
                      color: Color(0xFF2962FF), 
                      size: 35
                    ),
                  ),
                ),
                
                const SizedBox(height: 25),
                const Text(
                  "Choose Language",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A237E),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Select your preferred language",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                ),
                const SizedBox(height: 35),
                
                // 3. Enhanced List of Language Cards
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: languages.length,
                    itemBuilder: (context, index) {
                      final lang = languages[index];
                      bool isSelected = selectedLanguage == lang['name'];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedLanguage = lang['name']!;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF2962FF) : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected 
                                      ? const Color(0xFF2962FF).withValues(alpha: 0.1) 
                                      : Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                // Circular selection indicator
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF2962FF) : Colors.grey.shade300,
                                      width: isSelected ? 6 : 2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lang['name']!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 17,
                                        color: isSelected ? const Color(0xFF1A237E) : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      lang['native']!,
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFF2962FF) : Colors.blueGrey, 
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF2962FF), size: 24),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 4. Enhanced Bottom Button Section
                Container(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
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
                          onPressed: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const HomeScreen()),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2962FF),
                            minimumSize: const Size(double.infinity, 60),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            "Continue",
                            style: TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 18
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        "You can change this later in settings",
                        style: TextStyle(
                          color: Color(0xFF7986CB), 
                          fontSize: 14,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                    ],
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