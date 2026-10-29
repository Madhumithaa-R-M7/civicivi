import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Encrypted secure storage for sensitive JWT authentication tokens
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Preset backend server URLs
  static const String renderUrl = 'https://civicivi.onrender.com';
  static const String usbUrl = 'http://127.0.0.1:5000';
  static const String lanUrl = 'http://192.168.1.7:5000';
  static const String emulatorUrl = 'http://10.0.2.2:5000';

  static const String _keyBaseUrl = 'server_base_url';
  static String? _customBaseUrl;

  /// Load persisted custom base URL from SharedPreferences
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_keyBaseUrl);
      if (saved != null && saved.isNotEmpty) {
        _customBaseUrl = saved;
      }
    } catch (_) {}
  }

  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    // Default to USB reverse tunnel (127.0.0.1:5000) for connected physical device,
    // which works instantly over 'adb reverse tcp:5000 tcp:5000'
    return usbUrl;
  }

  static Future<void> setCustomBaseUrl(String url) async {
    final cleaned = url.trim().endsWith('/') ? url.trim().substring(0, url.trim().length - 1) : url.trim();
    _customBaseUrl = cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBaseUrl, cleaned);
    } catch (_) {}
  }

  /// Test connectivity to server /api/health
  static Future<bool> testConnection([String? targetUrl]) async {
    try {
      final target = targetUrl != null && targetUrl.isNotEmpty ? targetUrl : baseUrl;
      final uri = Uri.parse('$target/api/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Storage keys
  static const String _keyToken = 'auth_token';
  static const String _keyUser = 'auth_user';

  // -------------------------------------------------------------
  // Secure Session Management
  // -------------------------------------------------------------

  /// Store JWT token securely using encrypted storage and non-sensitive user metadata in preferences
  static Future<void> saveSession(String token, Map<String, dynamic> user) async {
    try {
      await _secureStorage.write(key: _keyToken, value: token);
    } catch (e) {
      debugPrint('Error writing to secure storage: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode(user));
  }

  /// Retrieve JWT token from secure storage, migrating from legacy preferences if present
  static Future<String?> getToken() async {
    try {
      final token = await _secureStorage.read(key: _keyToken);
      if (token != null && token.isNotEmpty) return token;
    } catch (e) {
      debugPrint('Error reading secure token: $e');
    }
    // Migration check from legacy SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_keyToken);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _keyToken, value: legacyToken);
        await prefs.remove(_keyToken);
      } catch (_) {}
      return legacyToken;
    }
    return null;
  }

  /// Retrieve cached user metadata
  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUser);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Check whether user session is currently authenticated
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Logout citizen by clearing secure storage and preferences
  static Future<void> logout() async {
    try {
      await _secureStorage.delete(key: _keyToken);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUser);
  }

  /// If a response indicates 401 or 403, invalidate local session
  static Future<void> _checkSessionExpiry(http.Response res) async {
    if (res.statusCode == 401 || res.statusCode == 403) {
      await logout();
    }
  }

  static Future<Map<String, String>> _getHeaders({bool isJson = true}) async {
    final headers = <String, String>{};
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // -------------------------------------------------------------
  // Authentication Endpoints
  // -------------------------------------------------------------

  /// Register citizen account (Email/Password or Phone)
  static Future<Map<String, dynamic>> register({
    required String name,
    String? email,
    String? phone,
    String? password,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/register');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name.trim(),
              if (email != null && email.isNotEmpty) 'email': email.trim().toLowerCase(),
              if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
              if (password != null && password.isNotEmpty) 'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 201 && data['success'] == true) {
        if (data['token'] != null && data['user'] != null) {
          await saveSession(data['token'], data['user']);
        }
      }
      return data;
    } on SocketException {
      return {'success': false, 'message': 'Unable to connect to server. Please check your network or server URL.'};
    } catch (e) {
      return {'success': false, 'message': 'Registration error: $e'};
    }
  }

  /// Login with email or phone + password
  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/login');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'identifier': identifier.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['success'] == true) {
        if (data['token'] != null && data['user'] != null) {
          await saveSession(data['token'], data['user']);
        }
      }
      return data;
    } on SocketException {
      return {'success': false, 'message': 'Connection refused. Is the CivicConnect server running at $baseUrl?'};
    } catch (e) {
      return {'success': false, 'message': 'Login error: $e'};
    }
  }

  /// Request 6-digit SMS OTP
  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/send-otp');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data;
      } catch (_) {
        return {
          'success': false,
          'message': res.body.isNotEmpty
              ? 'Server error (${res.statusCode}): ${res.body}'
              : 'Server returned HTTP ${res.statusCode}',
        };
      }
    } on SocketException {
      return {'success': false, 'message': 'Cannot reach SMS server. Check your network connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to request OTP: $e'};
    }
  }

  /// Verify 6-digit OTP code
  static Future<Map<String, dynamic>> verifyOtp({
    required String verificationId,
    required String otp,
    String? name,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/verify-otp');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'verificationId': verificationId,
              'otp': otp.trim(),
              if (name != null && name.isNotEmpty) 'name': name.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode == 200 && data['success'] == true) {
          if (data['token'] != null && data['user'] != null) {
            await saveSession(data['token'], data['user']);
          }
        }
        return data;
      } catch (_) {
        return {
          'success': false,
          'message': res.body.isNotEmpty
              ? 'Server error (${res.statusCode}): ${res.body}'
              : 'Server returned HTTP ${res.statusCode}',
        };
      }
    } on SocketException {
      return {'success': false, 'message': 'Connection failed during OTP verification.'};
    } catch (e) {
      return {'success': false, 'message': 'OTP verification error: $e'};
    }
  }

  /// Request Password Reset OTP via Email (Resend)
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/forgot-password');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim().toLowerCase()}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } on SocketException {
      return {'success': false, 'message': 'Unable to connect to server. Check your network or server URL.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to request password reset: $e'};
    }
  }

  /// Verify Password Reset OTP
  static Future<Map<String, dynamic>> verifyResetOtp({
    required String verificationId,
    required String otp,
    String? email,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/verify-reset-otp');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'verificationId': verificationId,
              'otp': otp.trim(),
              if (email != null && email.isNotEmpty) 'email': email.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } on SocketException {
      return {'success': false, 'message': 'Connection error during reset OTP verification.'};
    } catch (e) {
      return {'success': false, 'message': 'Verification error: $e'};
    }
  }

  /// Set New Password using verified reset token
  static Future<Map<String, dynamic>> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/reset-password');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'resetToken': resetToken,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data;
    } on SocketException {
      return {'success': false, 'message': 'Connection error while saving new password.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to reset password: $e'};
    }
  }

  /// Fetch citizen profile
  static Future<Map<String, dynamic>?> getProfile() async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/profile');
      final headers = await _getHeaders();
      final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      await _checkSessionExpiry(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['user'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_keyUser, jsonEncode(data['user']));
          return data['user'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update citizen profile (name, location)
  static Future<Map<String, dynamic>> updateProfile({String? name, String? location}) async {
    try {
      final url = Uri.parse('$baseUrl/api/auth/profile');
      final headers = await _getHeaders();
      final res = await http
          .put(
            url,
            headers: headers,
            body: jsonEncode({
              if (name != null) 'name': name.trim(),
              if (location != null) 'location': location.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));

      await _checkSessionExpiry(res);

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && data['user'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyUser, jsonEncode(data['user']));
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': 'Failed to update profile: $e'};
    }
  }

  // -------------------------------------------------------------
  // Complaints Endpoints
  // -------------------------------------------------------------

  /// Submit a complaint with multipart image upload & GPS coordinates
  static Future<Map<String, dynamic>> submitComplaint({
    required String category,
    required String description,
    required String priority,
    required String location,
    required double latitude,
    required double longitude,
    double? locationAccuracy,
    DateTime? locationCapturedAt,
    File? imageFile,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/complaints');
      final token = await getToken();

      final request = http.MultipartRequest('POST', url);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['category'] = category;
      request.fields['description'] = description;
      request.fields['priority'] = priority;
      request.fields['location'] = location;
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      if (locationAccuracy != null) {
        request.fields['locationAccuracy'] = locationAccuracy.toString();
      }
      if (locationCapturedAt != null) {
        request.fields['locationCapturedAt'] = locationCapturedAt.toIso8601String();
      }

      if (imageFile != null && await imageFile.exists()) {
        final stream = http.ByteStream(imageFile.openRead());
        final length = await imageFile.length();
        final multipartFile = http.MultipartFile(
          'image',
          stream,
          length,
          filename: imageFile.path.split(Platform.pathSeparator).last,
        );
        request.files.add(multipartFile);
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      await _checkSessionExpiry(response);

      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      } catch (_) {
        return {
          'success': false,
          'message': response.body.isNotEmpty
              ? 'Server response (${response.statusCode}): ${response.body}'
              : 'Server returned HTTP ${response.statusCode}',
        };
      }
    } on SocketException {
      return {'success': false, 'message': 'Unable to connect to server. Check your network connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Complaint submission failed: $e'};
    }
  }

  /// Get list of complaints (all or filtered by status / onlyMine)
  static Future<List<Map<String, dynamic>>> getComplaints({
    String? status,
    bool onlyMine = false,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (status != null && status.isNotEmpty) {
        queryParams['status'] = status;
      }
      if (onlyMine) {
        queryParams['onlyMine'] = 'true';
      }

      final uri = Uri.parse('$baseUrl/api/complaints').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final headers = await _getHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));

      await _checkSessionExpiry(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['complaints'] != null) {
          return (data['complaints'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting complaints: $e');
      return [];
    }
  }

  // -------------------------------------------------------------
  // Notifications Endpoints
  // -------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final url = Uri.parse('$baseUrl/api/notifications');
      final headers = await _getHeaders();
      final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      await _checkSessionExpiry(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['notifications'] != null) {
          return (data['notifications'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting notifications: $e');
      return [];
    }
  }

  static Future<void> markNotificationRead(int id) async {
    try {
      final url = Uri.parse('$baseUrl/api/notifications/$id/read');
      final headers = await _getHeaders();
      final res = await http.patch(url, headers: headers).timeout(const Duration(seconds: 8));
      await _checkSessionExpiry(res);
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // Rewards & Points Endpoints
  // -------------------------------------------------------------

  static Future<Map<String, dynamic>> getRewardsStats() async {
    try {
      final url = Uri.parse('$baseUrl/api/rewards/stats');
      final headers = await _getHeaders();
      final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      await _checkSessionExpiry(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return {
            'stats': data['stats'] as Map<String, dynamic>? ?? {},
            'history': data['history'] as List<dynamic>? ?? [],
          };
        }
      }
      return {'stats': {}, 'history': []};
    } catch (e) {
      debugPrint('Error getting rewards stats: $e');
      return {'stats': {}, 'history': []};
    }
  }

  // -------------------------------------------------------------
  // Mobile Algorithms Integration Endpoints
  // -------------------------------------------------------------

  /// Algorithm 11: Fetch nearby civic complaints within radius (meters) using Haversine Formula
  static Future<List<Map<String, dynamic>>> getNearbyComplaints({
    required double latitude,
    required double longitude,
    double radiusMeters = 1000,
    String? category,
  }) async {
    try {
      final queryParams = <String, String>{
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'radius': radiusMeters.toString(),
        if (category != null && category.isNotEmpty) 'category': category,
      };

      final uri = Uri.parse('$baseUrl/api/complaints/nearby').replace(queryParameters: queryParams);
      final headers = await _getHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));

      await _checkSessionExpiry(res);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['complaints'] != null) {
          return (data['complaints'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error getting nearby complaints: $e');
      return [];
    }
  }

  /// Algorithm 1: Real-time Rule-Based Complaint Classification from description text
  static Future<Map<String, dynamic>?> classifyText(String text) async {
    try {
      if (text.trim().isEmpty) return null;
      final url = Uri.parse('$baseUrl/api/complaints/classify');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text.trim()}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error classifying text: $e');
      return null;
    }
  }

  /// Algorithm 7: Multi-modal pre-submission duplicate screening (GPS + Text + Image)
  static Future<Map<String, dynamic>> checkDuplicate({
    double? latitude,
    double? longitude,
    String? category,
    String? description,
    File? imageFile,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/api/complaints/check-duplicate');
      final request = http.MultipartRequest('POST', url);

      if (latitude != null) request.fields['latitude'] = latitude.toString();
      if (longitude != null) request.fields['longitude'] = longitude.toString();
      if (category != null) request.fields['category'] = category;
      if (description != null) request.fields['description'] = description;

      if (imageFile != null && await imageFile.exists()) {
        final stream = http.ByteStream(imageFile.openRead());
        final length = await imageFile.length();
        final multipartFile = http.MultipartFile(
          'image',
          stream,
          length,
          filename: imageFile.path.split(Platform.pathSeparator).last,
        );
        request.files.add(multipartFile);
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'isDuplicate': false};
    } catch (e) {
      debugPrint('Error checking duplicate: $e');
      return {'isDuplicate': false};
    }
  }

  /// Algorithm 13 & 18: Retrieve complaint lifecycle audit trail & status history
  static Future<Map<String, dynamic>> getComplaintHistory(int complaintId) async {
    try {
      final url = Uri.parse('$baseUrl/api/complaints/$complaintId/history');
      final headers = await _getHeaders();
      final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 10));

      await _checkSessionExpiry(res);

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {'success': false, 'history': []};
    } catch (e) {
      debugPrint('Error getting complaint history: $e');
      return {'success': false, 'history': []};
    }
  }
}
