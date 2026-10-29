import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

class ReportIssueScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;
  const ReportIssueScreen({super.key, this.onBackToHome});

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  File? _selectedImage;
  String _currentAddress = "Location not captured yet";
  double? _latitude;
  double? _longitude;
  double? _locationAccuracy; // in meters
  DateTime? _locationCapturedAt;
  bool _isLocationManual = false;
  bool _isLocationConfirmed = false;
  bool _isFetchingLocation = false;
  String? _locationError;
  bool _isSubmitting = false;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  final ImagePicker _picker = ImagePicker();
  int _currentStep = 1;
  String? _selectedCategory;
  String? _selectedPriority = "Medium Priority";
  bool _isConfirmed = false;

  final TextEditingController _descriptionController = TextEditingController();
  Timer? _debounceTimer;
  String? _suggestedCategory;
  bool _isClassifying = false;

  final List<Map<String, dynamic>> _categories = [
    {'title': 'Roads & Traffic', 'desc': 'Potholes, road damage, missing signals', 'icon': Icons.traffic_rounded},
    {'title': 'Cleanliness & Waste Management', 'desc': 'Garbage accumulation, overflowing bins', 'icon': Icons.delete_outline_rounded},
    {'title': 'Water Supply & Sanitation', 'desc': 'Water leakage, pipe burst, sewage blockage', 'icon': Icons.opacity_rounded},
    {'title': 'Street & Public Lighting', 'desc': 'Damaged streetlights, dark public alleys', 'icon': Icons.lightbulb_outline_rounded},
    {'title': 'Infrastructure Issues', 'desc': 'Broken public footpaths, damaged bridges', 'icon': Icons.business_rounded},
    {'title': 'Public Facilities', 'desc': 'Public toilets, damaged bus stops, park benches', 'icon': Icons.home_work_rounded},
    {'title': 'Parks & Environment', 'desc': 'Fallen trees, untrimmed vegetation, park maintenance', 'icon': Icons.eco_rounded},
    {'title': 'Safety & Emergency Hazards', 'desc': 'Open manholes, live dangling wires, fire hazard', 'icon': Icons.shield_outlined},
    {'title': 'Administrative & Civic Services', 'desc': 'Municipal services, civic delays', 'icon': Icons.account_balance_rounded},
    {'title': 'Other Civic Issues', 'desc': 'Other public municipal issues', 'icon': Icons.more_horiz_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Algorithm 1: Real-time Rule-Based NLP classification of description text
  void _analyzeDescription(String text) {
    _debounceTimer?.cancel();
    if (text.trim().length < 5) {
      if (_suggestedCategory != null) {
        setState(() => _suggestedCategory = null);
      }
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _isClassifying = true);
      try {
        final result = await ApiService.classifyText(text.trim());
        if (!mounted) return;
        setState(() {
          _isClassifying = false;
          if (result != null && result['category'] != null && result['isConfident'] == true) {
            _suggestedCategory = result['category'];
            if (_selectedCategory == null || _selectedCategory == 'Other Civic Issues') {
              _selectedCategory = result['category'];
            }
          }
        });
      } catch (_) {
        if (mounted) setState(() => _isClassifying = false);
      }
    });
  }

  // -------------------------------------------------------------
  // Permission & Camera Handling
  // -------------------------------------------------------------

  /// Prompt camera with explanation and error handling
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo != null) {
        setState(() {
          _selectedImage = File(photo.path);
          _isLocationConfirmed = false;
        });

        // Prompt GPS capture automatically after taking photo
        await _requestAndAcquireGps(showRationaleFirst: false);
      }
    } on PlatformException catch (e) {
      debugPrint("Camera platform exception: $e");
      if (!mounted) return;
      _showCameraPermissionDialog();
    } catch (e) {
      debugPrint("Unexpected camera error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Camera error: $e")),
      );
    }
  }

  void _showCameraPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_rounded, color: Color(0xFF2962FF)),
            SizedBox(width: 10),
            Text("Camera Permission Needed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "CivicConnect requires camera access to capture photographic evidence of civic issues. Please grant camera permission in App Settings.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2962FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Open Settings", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Fresh Device GPS Location Capture
  // -------------------------------------------------------------

  /// Request and acquire fresh GPS location with user rationale & error handling
  Future<void> _requestAndAcquireGps({bool showRationaleFirst = true}) async {
    setState(() {
      _isFetchingLocation = true;
      _locationError = null;
    });

    try {
      // 1. Check if device location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _isFetchingLocation = false;
          _locationError = "Location services (GPS) are turned off on your device.";
        });
        _showLocationServiceDialog();
        return;
      }

      // 2. Check location permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        if (showRationaleFirst) {
          final bool? proceed = await _showLocationRationaleDialog();
          if (proceed != true) {
            setState(() {
              _isFetchingLocation = false;
              _locationError = "Location permission is required to capture issue coordinates.";
            });
            return;
          }
        }

        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _isFetchingLocation = false;
          _locationError = "Location permission denied. GPS coordinates could not be captured.";
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isFetchingLocation = false;
          _locationError = "Location permission permanently denied. Please enable it in Settings.";
        });
        _showPermanentlyDeniedDialog();
        return;
      }

      // 3. Obtain fresh device location (not cached or hardcoded)
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final double lat = position.latitude;
      final double lng = position.longitude;
      final double accuracy = position.accuracy;
      final DateTime captureTime = position.timestamp;

      String address = "Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          final Placemark p = placemarks.first;
          final parts = [p.street, p.subLocality, p.locality, p.administrativeArea, p.postalCode]
              .where((s) => s != null && s.trim().isNotEmpty)
              .toSet()
              .toList();
          if (parts.isNotEmpty) {
            address = parts.join(", ");
          }
        }
      } catch (_) {
        // Fallback to coordinates string
      }

      if (!mounted) return;
      setState(() {
        _latitude = lat;
        _longitude = lng;
        _locationAccuracy = accuracy;
        _locationCapturedAt = captureTime;
        _currentAddress = address;
        _isLocationManual = false;
        _isLocationConfirmed = true;
        _isFetchingLocation = false;
        _locationError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingLocation = false;
        _locationError = "Failed to acquire GPS location: $e";
      });
    }
  }

  Future<bool?> _showLocationRationaleDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_on_rounded, color: Color(0xFF2962FF)),
            SizedBox(width: 8),
            Text("Location Access", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          "CivicConnect requires your GPS location to tag the civic complaint with precise coordinates. This helps municipal field workers locate and resolve the issue quickly.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Not Now"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
            child: const Text("Allow Location", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_disabled_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text("Enable Location", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          "GPS / Location service is currently disabled on your device. Turn it on so we can record the complaint coordinates.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
            child: const Text("Open Location Settings", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPermanentlyDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Permission Required", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          "Location permission is permanently denied for CivicConnect. Please grant permission in App Settings to enable GPS tagging.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Dismiss"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
            child: const Text("Open App Settings", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Manual address / location fallback dialog if user is indoors or GPS unavailable
  Future<void> _showManualLocationDialog() async {
    final addressCtrl = TextEditingController(text: _currentAddress.startsWith("Lat:") ? "" : _currentAddress);
    final latCtrl = TextEditingController(text: _latitude != null ? _latitude.toString() : "");
    final lngCtrl = TextEditingController(text: _longitude != null ? _longitude.toString() : "");

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_location_alt_rounded, color: Color(0xFF2962FF)),
            SizedBox(width: 8),
            Text("Manual Location Input", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "If GPS is unavailable, enter the street address and optional coordinates. Note: This will be clearly flagged as manually selected.",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: "Street Address / Landmark *",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Latitude (Optional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.north_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Longitude (Optional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.east_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (addressCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please enter a street address or landmark")),
                );
                return;
              }
              final parsedLat = double.tryParse(latCtrl.text.trim()) ?? 19.0760; // Default municipal center fallback
              final parsedLng = double.tryParse(lngCtrl.text.trim()) ?? 72.8777;
              setState(() {
                _currentAddress = addressCtrl.text.trim();
                _latitude = parsedLat;
                _longitude = parsedLng;
                _locationAccuracy = null;
                _locationCapturedAt = DateTime.now();
                _isLocationManual = true;
                _isLocationConfirmed = true;
                _locationError = null;
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF)),
            child: const Text("Save Location", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Open interactive OpenStreetMap preview dialog using flutter_map
  void _showMapPreviewModal() {
    if (_latitude == null || _longitude == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.map_rounded, color: Color(0xFF2962FF)),
                    SizedBox(width: 8),
                    Text(
                      "GPS Location Preview",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Lat: ${_latitude!.toStringAsFixed(6)}, Lng: ${_longitude!.toStringAsFixed(6)}",
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(_latitude!, _longitude!),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.civicconnect.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_latitude!, _longitude!),
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 42),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.place_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _isLocationConfirmed = true);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2962FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Use This Location", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Voice Input
  // -------------------------------------------------------------

  Future<void> _listenVoice() async {
    bool available = await _speech.initialize(
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Speech error: ${error.errorMsg}")),
        );
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == "done" || status == "notListening") {
          setState(() => _isListening = false);
        }
      },
    );

    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Speech recognition not available on this device")),
      );
      return;
    }

    if (!_isListening) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "en_IN",
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _descriptionController.text = result.recognizedWords;
          });
          _analyzeDescription(result.recognizedWords);
        },
      );
    } else {
      setState(() => _isListening = false);
      await _speech.stop();
    }
  }

  /// Algorithm 7: User-friendly dialog warning about nearby duplicate complaint before submission
  Future<bool?> _showDuplicateWarningDialog(Map<String, dynamic> duplicateData) {
    final spatiotemporal = duplicateData['spatiotemporal'] as Map<String, dynamic>?;
    final topMatch = spatiotemporal?['topMatch'] as Map<String, dynamic>?;
    final exactMatch = duplicateData['exactMatch'] as Map<String, dynamic>?;
    final visualMatches = duplicateData['visualMatches'] as List<dynamic>?;

    final int? duplicateId = topMatch?['complaint_id'] ??
        exactMatch?['complaint_id'] ??
        (visualMatches != null && visualMatches.isNotEmpty ? visualMatches[0]['complaint_id'] : null);

    final num? distance = topMatch?['distanceMeters'];
    final String matchedCategory = topMatch?['category'] ?? exactMatch?['category'] ?? "Civic Issue";
    final num confidence = duplicateData['confidenceScore'] ?? 80;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Similar Report Nearby",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (duplicateId != null)
                    Row(
                      children: [
                        const Icon(Icons.tag_rounded, size: 16, color: Color(0xFF2962FF)),
                        const SizedBox(width: 6),
                        Text(
                          "Existing Complaint #$duplicateId",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2962FF)),
                        ),
                      ],
                    ),
                  if (distance != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.near_me_rounded, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          "Distance: ${distance.toStringAsFixed(0)}m from your location",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.category_rounded, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Category: $matchedCategory",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined, size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        "Match Confidence: ${confidence.toStringAsFixed(0)}%",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "A very similar issue has already been reported nearby. Submitting will link your report as corroborating evidence and upvote it in the municipal dispatch queue.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Review My Report", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2962FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text("Submit & Link", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Final Submission to Backend
  // -------------------------------------------------------------

  Future<void> _submitReport() async {
    if (_isSubmitting) return;

    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please capture a photo of the civic issue")),
      );
      setState(() => _currentStep = 1);
      return;
    }

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Valid GPS coordinates are required before submitting")),
      );
      setState(() => _currentStep = 1);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Algorithm 7: Multi-modal pre-submission duplicate screening
      final dupResult = await ApiService.checkDuplicate(
        latitude: _latitude,
        longitude: _longitude,
        category: _selectedCategory,
        description: _descriptionController.text.trim(),
        imageFile: _selectedImage,
      );

      if (!mounted) return;

      if (dupResult['isDuplicate'] == true) {
        setState(() => _isSubmitting = false);
        final proceed = await _showDuplicateWarningDialog(dupResult);
        if (proceed != true) {
          return;
        }
        if (!mounted) return;
        setState(() => _isSubmitting = true);
      }

      final res = await ApiService.submitComplaint(
        category: _selectedCategory ?? 'General Civic Issue',
        description: _descriptionController.text.trim(),
        priority: _selectedPriority ?? 'Medium Priority',
        location: _currentAddress,
        latitude: _latitude!,
        longitude: _longitude!,
        locationAccuracy: _locationAccuracy,
        locationCapturedAt: _locationCapturedAt ?? DateTime.now(),
        imageFile: _selectedImage,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (res['success'] == true) {
        final complaintId = res['complaint'] != null ? res['complaint']['id'] : '';
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 64),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Complaint Registered",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 8),
                if (complaintId != '')
                  Text(
                    "Complaint ID: #$complaintId",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2962FF)),
                  ),
                const SizedBox(height: 10),
                const Text(
                  "Your photographic proof and GPS coordinates have been securely saved in PostgreSQL. Repair teams have been alerted.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (widget.onBackToHome != null) {
                      widget.onBackToHome!();
                    } else {
                      Navigator.pop(context, 'return_home');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2962FF),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Return to Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? "Failed to submit complaint"),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error submitting complaint: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // -------------------------------------------------------------
  // Screen Layout & Steps
  // -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            _buildProgressBar(),
            const SizedBox(height: 10),
            Expanded(child: _buildCurrentStepView()),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
      default:
        return _buildStep1();
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 10)],
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A237E), size: 18),
              onPressed: () {
                if (_currentStep > 1) {
                  setState(() => _currentStep--);
                } else {
                  if (widget.onBackToHome != null) {
                    widget.onBackToHome!();
                  } else {
                    Navigator.pop(context, 'return_home');
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            "Report Civic Issue",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A237E),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStepCircle("1", isActive: _currentStep >= 1, isDone: _currentStep > 1),
          _buildStepLine(highlight: _currentStep >= 2),
          _buildStepCircle("2", isActive: _currentStep >= 2, isDone: _currentStep > 2),
          _buildStepLine(highlight: _currentStep >= 3),
          _buildStepCircle("3", isActive: _currentStep >= 3, isDone: _currentStep > 3),
          _buildStepLine(highlight: _currentStep >= 4),
          _buildStepCircle("4", isActive: _currentStep >= 4, isDone: _currentStep > 4),
        ],
      ),
    );
  }

  // --- STEP 1: PHOTO & REAL-TIME GPS TAG ---
  Widget _buildStep1() {
    final bool hasValidLocation = _latitude != null && _longitude != null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text(
                  "Capture Photo & Location",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A237E)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    "Take a photo of the civic problem. Your device's exact GPS coordinates will be captured automatically.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 14),

                // Photo Capture Card
                Center(
                  child: GestureDetector(
                    onTap: _pickImageFromCamera,
                    child: Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2962FF).withAlpha(20),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                        image: _selectedImage != null
                            ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                            : null,
                        border: Border.all(
                          color: _selectedImage == null
                              ? const Color(0xFF2962FF).withAlpha(60)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _selectedImage == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2962FF).withAlpha(15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.photo_camera_rounded, size: 48, color: Color(0xFF2962FF)),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  "Tap to Open Camera",
                                  style: TextStyle(
                                    color: Color(0xFF2962FF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Requires Camera & GPS permissions",
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ),
                ),

                if (_selectedImage != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickImageFromCamera,
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text("Retake Photo"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2962FF),
                          side: const BorderSide(color: Color(0xFF2962FF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // GPS Information & Verification Card
                _buildGpsCard(),

                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
        _buildNavigationButtons(
          onNext: () {
            if (_selectedImage == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please capture a photo first")),
              );
              return;
            }
            if (!hasValidLocation) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Valid location is required. Please capture GPS or enter manual location.")),
              );
              return;
            }
            setState(() => _currentStep = 2);
          },
          enabled: _selectedImage != null && hasValidLocation,
          showBack: false,
        ),
      ],
    );
  }

  /// Comprehensive, responsive GPS Card for small Android screens
  Widget _buildGpsCard() {
    if (_isFetchingLocation) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2962FF).withAlpha(40)),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF2962FF)),
            ),
            SizedBox(width: 14),
            Flexible(
              child: Text(
                "Acquiring high-accuracy GPS coordinates...",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
              ),
            ),
          ],
        ),
      );
    }

    if (_locationError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_off_rounded, color: Colors.red, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Location Not Available",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: _showManualLocationDialog,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text("Enter Manually", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _locationError!,
              style: TextStyle(color: Colors.red.shade800, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _requestAndAcquireGps(showRationaleFirst: false),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text("Retry GPS", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2962FF),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_latitude != null && _longitude != null) {
      final isPoorAccuracy = _locationAccuracy != null && _locationAccuracy! > 50.0;
      final captureTimeStr = _locationCapturedAt != null
          ? "${_locationCapturedAt!.hour.toString().padLeft(2, '0')}:${_locationCapturedAt!.minute.toString().padLeft(2, '0')}:${_locationCapturedAt!.second.toString().padLeft(2, '0')}, ${_locationCapturedAt!.day.toString().padLeft(2, '0')}/${_locationCapturedAt!.month.toString().padLeft(2, '0')}/${_locationCapturedAt!.year}"
          : "Captured just now";

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isLocationManual ? Colors.orange.shade300 : const Color(0xFF2962FF).withAlpha(60),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (_isLocationManual ? Colors.orange : const Color(0xFF2962FF)).withAlpha(15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title + Verification Badge
            Row(
              children: [
                Icon(
                  _isLocationManual ? Icons.edit_location_alt_rounded : Icons.gps_fixed_rounded,
                  color: _isLocationManual ? Colors.orange.shade800 : const Color(0xFF2962FF),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isLocationManual ? "Manual Location Selected" : "GPS Location Captured",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _isLocationManual ? Colors.orange.shade900 : const Color(0xFF1A237E),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_isLocationManual ? Colors.orange : Colors.green).withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (_isLocationManual ? Colors.orange : Colors.green).withAlpha(80),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLocationManual ? Icons.handyman_rounded : Icons.verified_rounded,
                        size: 11,
                        color: _isLocationManual ? Colors.orange.shade800 : Colors.green.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isLocationManual ? "MANUAL" : "GPS VERIFIED",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: _isLocationManual ? Colors.orange.shade800 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Exact Coordinates Display (Separate lines, clear labels, no overlap)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line 1: Latitude
                  Row(
                    children: [
                      const Icon(Icons.explore_outlined, size: 15, color: Color(0xFF2962FF)),
                      const SizedBox(width: 8),
                      const Text(
                        "Latitude:",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${_latitude!.toStringAsFixed(6)}°",
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Line 2: Longitude
                  Row(
                    children: [
                      const Icon(Icons.explore_outlined, size: 15, color: Color(0xFF2962FF)),
                      const SizedBox(width: 8),
                      const Text(
                        "Longitude:",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${_longitude!.toStringAsFixed(6)}°",
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                  ),

                  // Line 3: Accuracy in meters
                  Row(
                    children: [
                      Icon(
                        Icons.track_changes_rounded,
                        size: 15,
                        color: isPoorAccuracy ? Colors.orange.shade800 : Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Accuracy:",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _locationAccuracy != null
                              ? "±${_locationAccuracy!.toStringAsFixed(1)} meters"
                              : "Standard GPS (~10 m)",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isPoorAccuracy ? Colors.orange.shade900 : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Line 4: Capture timestamp (full date and time, no clipping)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      const Text(
                        "Captured At:",
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          captureTimeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (isPoorAccuracy) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "GPS accuracy is low (±${_locationAccuracy!.toStringAsFixed(0)}m). For highest precision, step under open sky and tap Refresh.",
                        style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Resolved Location Address (full text wrapping, no maxLines truncation)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_rounded, size: 18, color: Color(0xFF2962FF)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "RESOLVED ADDRESS",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currentAddress,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1E293B),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Action Buttons: Location Confirmed, View on Map, Refresh GPS
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _isLocationConfirmed = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Location confirmed! Tap Continue to proceed."),
                        backgroundColor: Color(0xFF2962FF),
                      ),
                    );
                  },
                  icon: Icon(
                    _isLocationConfirmed ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                    size: 16,
                  ),
                  label: Text(_isLocationConfirmed ? "Location Confirmed" : "Confirm Location"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLocationConfirmed ? Colors.green.shade700 : const Color(0xFF2962FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showMapPreviewModal,
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text("View on Map"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2962FF),
                    side: const BorderSide(color: Color(0xFF2962FF)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _requestAndAcquireGps(showRationaleFirst: false),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text("Refresh GPS"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade800,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.location_searching_rounded, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          const Text(
            "No location recorded yet",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 4),
          const Text(
            "Taking a photo will automatically acquire your current GPS coordinates.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _requestAndAcquireGps(showRationaleFirst: true),
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text("Capture GPS Now"),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _showManualLocationDialog,
                child: const Text("Enter Manually"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- STEP 2: CATEGORY ---
  Widget _buildStep2() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Select Issue Category",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 16),
                _buildSectionHeader("Location Attached"),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location_rounded, color: Color(0xFF2962FF), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _currentAddress,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader("Civic Categories"),
                const SizedBox(height: 8),
                ..._categories.map((cat) => _buildCategoryTile(cat)),
              ],
            ),
          ),
        ),
        _buildNavigationButtons(
          onNext: () => setState(() => _currentStep = 3),
          enabled: _selectedCategory != null,
        ),
      ],
    );
  }

  // --- STEP 3: DESCRIPTION & PRIORITY ---
  Widget _buildStep3() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Additional Details",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader("Description of the Problem"),
                _buildDescriptionField(),
                if (_isClassifying) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2962FF)),
                      ),
                      const SizedBox(width: 8),
                      Text("Analyzing text for category recommendation...", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ] else if (_suggestedCategory != null) ...[
                  const SizedBox(height: 8),
                  _buildCategorySuggestionChip(),
                ],
                const SizedBox(height: 20),
                _buildSectionHeader("Voice Description (Optional)"),
                _buildVoiceMessageButton(),
                const SizedBox(height: 25),
                _buildSectionHeader("Priority Level"),
                const SizedBox(height: 10),
                _buildPriorityTile("Low Priority", "Non-urgent, can be scheduled normally", Icons.keyboard_double_arrow_down_rounded, Colors.blue),
                _buildPriorityTile("Medium Priority", "Requires attention within reasonable time", Icons.remove_circle_outline_rounded, Colors.orange),
                _buildPriorityTile("High Priority", "Critical or safety hazard needing rapid action", Icons.keyboard_double_arrow_up_rounded, Colors.red),
              ],
            ),
          ),
        ),
        _buildNavigationButtons(
          onNext: () {
            if (_descriptionController.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide a brief description of the issue")));
            } else {
              setState(() => _currentStep = 4);
            }
          },
          enabled: _selectedPriority != null,
        ),
      ],
    );
  }

  // --- STEP 4: REVIEW & SUBMISSION ---
  Widget _buildStep4() {
    final captureTimeStr = _locationCapturedAt != null
        ? "${_locationCapturedAt!.hour.toString().padLeft(2, '0')}:${_locationCapturedAt!.minute.toString().padLeft(2, '0')}:${_locationCapturedAt!.second.toString().padLeft(2, '0')}, ${_locationCapturedAt!.day.toString().padLeft(2, '0')}/${_locationCapturedAt!.month.toString().padLeft(2, '0')}/${_locationCapturedAt!.year}"
        : "Captured with submission";

    Color priorityColor = Colors.orange;
    if (_selectedPriority == "High Priority") priorityColor = Colors.red;
    if (_selectedPriority == "Low Priority") priorityColor = Colors.blue;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  "Review & Submit",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Please verify all details of your report before submitting to municipal authorities.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),

                // Card 1: Captured Photo Evidence Preview with Retake Action
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF2962FF).withAlpha(15), blurRadius: 14, offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: Stack(
                          children: [
                            _selectedImage != null
                                ? Image.file(_selectedImage!, height: 200, width: double.infinity, fit: BoxFit.cover)
                                : Container(
                                    height: 180,
                                    width: double.infinity,
                                    color: const Color(0xFFF1F5F9),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_not_supported_rounded, size: 48, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text("No photo attached", style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(160),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded, size: 14, color: Colors.greenAccent),
                                    SizedBox(width: 4),
                                    Text(
                                      "Photo Evidence",
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Camera Photo Proof",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A237E)),
                            ),
                            TextButton.icon(
                              onPressed: _pickImageFromCamera,
                              icon: const Icon(Icons.camera_alt_outlined, size: 16),
                              label: const Text("Retake Photo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF2962FF),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card 2: Location & GPS Proof Details
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isLocationManual ? Colors.orange.shade200 : const Color(0xFF2962FF).withAlpha(40),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 3))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isLocationManual ? Icons.edit_location_alt_rounded : Icons.gps_fixed_rounded,
                            color: _isLocationManual ? Colors.orange.shade800 : const Color(0xFF2962FF),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "LOCATION & GPS PROOF",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_isLocationManual ? Colors.orange : Colors.green).withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isLocationManual ? "MANUAL ENTRY" : "GPS VERIFIED",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isLocationManual ? Colors.orange.shade800 : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Address with full wrapping
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_rounded, size: 16, color: Color(0xFF2962FF)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Resolved Address",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentAddress,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A237E),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                      ),

                      // Coordinates Display (Separate lines, clear labels)
                      if (_latitude != null && _longitude != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.explore_outlined, size: 15, color: Color(0xFF2962FF)),
                            const SizedBox(width: 8),
                            const Text(
                              "Latitude: ",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                            ),
                            Expanded(
                              child: Text(
                                "${_latitude!.toStringAsFixed(6)}°",
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.explore_outlined, size: 15, color: Color(0xFF2962FF)),
                            const SizedBox(width: 8),
                            const Text(
                              "Longitude: ",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                            ),
                            Expanded(
                              child: Text(
                                "${_longitude!.toStringAsFixed(6)}°",
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Accuracy & Timestamp
                      Row(
                        children: [
                          const Icon(Icons.track_changes_rounded, size: 15, color: Colors.green),
                          const SizedBox(width: 8),
                          const Text(
                            "Accuracy: ",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                          Expanded(
                            child: Text(
                              _locationAccuracy != null
                                  ? "±${_locationAccuracy!.toStringAsFixed(1)} meters"
                                  : "Standard GPS",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          const Text(
                            "Timestamp: ",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                          Expanded(
                            child: Text(
                              captureTimeStr,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card 3: Issue Categorization & Priority
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 3))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.category_rounded, size: 18, color: Color(0xFF2962FF)),
                          SizedBox(width: 8),
                          Text(
                            "ISSUE CLASSIFICATION",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2962FF).withAlpha(15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.grid_view_rounded, size: 20, color: Color(0xFF2962FF)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Category",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                                Text(
                                  _selectedCategory ?? "General Civic Issue",
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: priorityColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.flag_rounded, size: 20, color: priorityColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Priority Level",
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                                Text(
                                  _selectedPriority ?? "Medium Priority",
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: priorityColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card 4: Detailed Description with Full Word Wrapping
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 3))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.notes_rounded, size: 18, color: Color(0xFF2962FF)),
                              SizedBox(width: 8),
                              Text(
                                "PROBLEM DESCRIPTION",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => setState(() => _currentStep = 3),
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            child: const Text("Edit", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          _descriptionController.text.trim().isNotEmpty
                              ? _descriptionController.text.trim()
                              : "No description provided.",
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF334155),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card 5: Transparency & Audit Notice
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.security_rounded, color: Color(0xFF2962FF), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "GPS coordinates and photographic evidence are cryptographically hashed and stored in PostgreSQL to ensure transparency.",
                          style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Confirmation Checkbox
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _isConfirmed ? const Color(0xFF2962FF).withAlpha(80) : Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _isConfirmed,
                        activeColor: const Color(0xFF2962FF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: _isSubmitting ? null : (val) => setState(() => _isConfirmed = val ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          "I confirm that this report describes a real civic issue and the captured photo is genuine.",
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),
              ],
            ),
          ),
        ),

        // Bottom Submission Controls (SafeArea protected, accessible)
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10, offset: const Offset(0, -4))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => setState(() => _currentStep = 3),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      side: const BorderSide(color: Color(0xFF2962FF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("Back / Edit", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isConfirmed && !_isSubmitting) ? _submitReport : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      disabledBackgroundColor: Colors.grey.shade300,
                      minimumSize: const Size(0, 52),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            "Submit Complaint",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- UI WIDGET HELPERS ---
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.grey, letterSpacing: 1.1),
      ),
    );
  }


  Widget _buildCategoryTile(Map<String, dynamic> cat) {
    final bool isSelected = _selectedCategory == cat['title'];
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = cat['title']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF2962FF) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2962FF).withAlpha(isSelected ? 25 : 12),
                shape: BoxShape.circle,
              ),
              child: Icon(cat['icon'], color: const Color(0xFF2962FF), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cat['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                  const SizedBox(height: 2),
                  Text(cat['desc'], style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle_rounded, color: Color(0xFF2962FF), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8)],
      ),
      child: TextField(
        controller: _descriptionController,
        maxLines: 4,
        onChanged: _analyzeDescription,
        decoration: InputDecoration(
          hintText: "Describe the civic issue in detail (location landmarks, size, urgency)...",
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          contentPadding: const EdgeInsets.all(16),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCategorySuggestionChip() {
    final bool isApplied = _selectedCategory == _suggestedCategory;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2962FF).withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2962FF).withAlpha(40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF2962FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "AI Category Recommendation",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                Text(
                  _suggestedCategory!,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                ),
              ],
            ),
          ),
          if (!isApplied)
            ElevatedButton(
              onPressed: () {
                setState(() => _selectedCategory = _suggestedCategory);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Category set to '$_suggestedCategory'")),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2962FF),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Apply", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check, color: Colors.green, size: 14),
                  SizedBox(width: 4),
                  Text("Selected", style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceMessageButton() {
    return GestureDetector(
      onTap: _listenVoice,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: _isListening ? Colors.red.withAlpha(20) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _isListening ? Colors.red : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 8)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isListening ? Icons.mic : Icons.mic_none_rounded,
              color: _isListening ? Colors.red : const Color(0xFF2962FF),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _isListening ? "Listening... Speak description now" : "Tap to Speak Description",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: _isListening ? Colors.red : const Color(0xFF2962FF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityTile(String title, String desc, IconData icon, Color color) {
    final bool isSelected = _selectedPriority == title;
    return GestureDetector(
      onTap: () => setState(() => _selectedPriority = title),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 6)],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                  Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildStepCircle(String step, {required bool isActive, required bool isDone}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isDone ? Colors.green : (isActive ? const Color(0xFF2962FF) : Colors.grey.shade200),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: isDone
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Text(step, style: TextStyle(color: isActive ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildStepLine({required bool highlight}) {
    return Expanded(
      child: Container(
        height: 3,
        color: highlight ? const Color(0xFF2962FF) : Colors.grey.shade200,
      ),
    );
  }

  Widget _buildNavigationButtons({required VoidCallback onNext, required bool enabled, bool showBack = true}) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 10,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: Row(
          children: [
            if (showBack) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: const BorderSide(color: Color(0xFF2962FF)),
                  ),
                  child: const Text("Back", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              flex: showBack ? 1 : 2,
              child: ElevatedButton(
                onPressed: enabled ? onNext : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2962FF),
                  disabledBackgroundColor: Colors.grey.shade300,
                  minimumSize: const Size(0, 52),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Continue", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}