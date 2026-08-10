// import 'dart:convert';
// import 'dart:io';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
// import '../config.dart';
// import 'package:flutter/material.dart';
// import '../main.dart';
// import '../screens/login_screen.dart';
// import 'notification_service.dart';
// import 'push_service.dart';

// class ApiService {
//   static const _tokenKey = 'access_token';
//   static const _refreshKey = 'refresh_token';

//   // ---------- Token storage ----------

//   static Future<void> _saveTokens(String access, String refresh) async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString(_tokenKey, access);
//     await prefs.setString(_refreshKey, refresh);
//   }

//   static Future<String?> getAccessToken() async {
//     final prefs = await SharedPreferences.getInstance();
//     return prefs.getString(_tokenKey);
//   }

//   static Future<void> logout() async {
//     await PushService.unregisterToken();
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove(_tokenKey);
//     await prefs.remove(_refreshKey);
//     NotificationService.instance.reset();
//   }

//   static Future<bool> isLoggedIn() async {
//     final token = await getAccessToken();
//     return token != null;
//   }

//   static Future<Map<String, String>> _authHeaders() async {
//     final token = await getAccessToken();
//     return {
//       'Content-Type': 'application/json',
//       if (token != null) 'Authorization': 'Bearer $token',
//     };
//   }

//   static Future<bool> _tryRefreshToken() async {
//     final prefs = await SharedPreferences.getInstance();
//     final refreshToken = prefs.getString(_refreshKey);
//     if (refreshToken == null) return false;

//     try {
//       final res = await http.post(
//         Uri.parse('$kApiBaseUrl/token/refresh/'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'refresh': refreshToken}),
//       );
//       if (res.statusCode == 200) {
//         final data = jsonDecode(res.body);
//         await prefs.setString(_tokenKey, data['access']);
//         return true;
//       }
//     } catch (_) {}
//     return false;
//   }

//   static Future<bool> tryRefreshToken() => _tryRefreshToken();

//   static Future<void> _forceLogout() async {
//     await logout();
//     final ctx = navigatorKey.currentContext;
//     if (ctx != null) {
//       Navigator.of(ctx).pushAndRemoveUntil(
//         MaterialPageRoute(builder: (_) => const LoginScreen()),
//         (route) => false,
//       );
//     }
//   }

//   // ---------- Auth ----------

//   static Future<void> login(String username, String password) async {
//     final res = await http.post(
//       Uri.parse('$kApiBaseUrl/token/'),
//       headers: {'Content-Type': 'application/json'},
//       body: jsonEncode({'username': username, 'password': password}),
//     );

//     if (res.statusCode == 200) {
//       final data = jsonDecode(res.body);
//       await _saveTokens(data['access'], data['refresh']);
//       PushService.registerToken();
//     } else {
//       throw Exception(
//         'Login failed. Please check your username and password with your admin.',
//       );
//     }
//   }

//   static String _extractFirstError(dynamic body) {
//     if (body is Map) {
//       final firstKey = body.keys.first;
//       final firstVal = body[firstKey];
//       if (firstVal is List && firstVal.isNotEmpty) return '${firstVal.first}';
//       return '$firstVal';
//     }
//     if (body is List && body.isNotEmpty) return '${body.first}';
//     return 'Something went wrong. Please try again.';
//   }

//   // ---------- Vendor profile ----------

//   static Future<Map<String, dynamic>> getMyProfile() async {
//     var headers = await _authHeaders();
//     var res = await http.get(
//       Uri.parse('$kApiBaseUrl/vendors/me/'),
//       headers: headers,
//     );
//     if (res.statusCode == 401) {
//       if (await _tryRefreshToken()) {
//         headers = await _authHeaders();
//         res = await http.get(
//           Uri.parse('$kApiBaseUrl/vendors/me/'),
//           headers: headers,
//         );
//       } else {
//         await _forceLogout();
//         throw Exception('Session expired. Please log in again.');
//       }
//     }
//     if (res.statusCode == 200) return jsonDecode(res.body);
//     throw Exception('Could not load your profile.');
//   }

//   static Future<void> setAvailability(bool isAvailable) async {
//     var headers = await _authHeaders();
//     var res = await http.patch(
//       Uri.parse('$kApiBaseUrl/vendors/me/availability/'),
//       headers: headers,
//       body: jsonEncode({'is_available': isAvailable}),
//     );
//     if (res.statusCode == 401) {
//       if (await _tryRefreshToken()) {
//         headers = await _authHeaders();
//         res = await http.patch(
//           Uri.parse('$kApiBaseUrl/vendors/me/availability/'),
//           headers: headers,
//           body: jsonEncode({'is_available': isAvailable}),
//         );
//       } else {
//         await _forceLogout();
//         throw Exception('Session expired. Please log in again.');
//       }
//     }
//     if (res.statusCode != 200) {
//       throw Exception('Could not update availability.');
//     }
//   }

//   // ---------- Assigned jobs ----------

//   static Future<List<dynamic>> getAssignedJobs() async {
//     var headers = await _authHeaders();
//     var res = await http.get(
//       Uri.parse('$kApiBaseUrl/bookings/assigned/'),
//       headers: headers,
//     );
//     if (res.statusCode == 401) {
//       if (await _tryRefreshToken()) {
//         headers = await _authHeaders();
//         res = await http.get(
//           Uri.parse('$kApiBaseUrl/bookings/assigned/'),
//           headers: headers,
//         );
//       } else {
//         await _forceLogout();
//         throw Exception('Session expired. Please log in again.');
//       }
//     }
//     if (res.statusCode == 200) return jsonDecode(res.body);
//     throw Exception('Could not load your jobs.');
//   }

//   static Future<void> uploadStartPhoto({
//     required int bookingId,
//     required File imageFile,
//     required double latitude,
//     required double longitude,
//   }) async {
//     final uri = Uri.parse('$kApiBaseUrl/bookings/$bookingId/start-photo/');

//     Future<http.Response> sendRequest() async {
//       final token = await getAccessToken();
//       final request = http.MultipartRequest('POST', uri);
//       if (token != null) request.headers['Authorization'] = 'Bearer $token';
//       request.fields['latitude'] = latitude.toStringAsFixed(6);
//       request.fields['longitude'] = longitude.toStringAsFixed(6);
//       request.files.add(
//         await http.MultipartFile.fromPath('image', imageFile.path),
//       );
//       final streamed = await request.send();
//       return http.Response.fromStream(streamed);
//     }

//     var res = await sendRequest();

//     if (res.statusCode == 401) {
//       if (await _tryRefreshToken()) {
//         res = await sendRequest();
//       } else {
//         await _forceLogout();
//         throw Exception('Session expired. Please log in again.');
//       }
//     }

//     if (res.statusCode != 201) {
//       throw Exception(_extractFirstError(jsonDecode(res.body)));
//     }
//   }

//   static Future<void> completeJob(int bookingId) async {
//     var headers = await _authHeaders();
//     var res = await http.post(
//       Uri.parse('$kApiBaseUrl/bookings/$bookingId/complete/'),
//       headers: headers,
//     );
//     if (res.statusCode == 401) {
//       if (await _tryRefreshToken()) {
//         headers = await _authHeaders();
//         res = await http.post(
//           Uri.parse('$kApiBaseUrl/bookings/$bookingId/complete/'),
//           headers: headers,
//         );
//       } else {
//         await _forceLogout();
//         throw Exception('Session expired. Please log in again.');
//       }
//     }
//     if (res.statusCode != 200) {
//       throw Exception(_extractFirstError(jsonDecode(res.body)));
//     }
//   }

//   static Future<Map<String, dynamic>> getVendorProfile() async {
//     final headers = await _authHeaders();
//     final res = await http.get(
//       Uri.parse('$kApiBaseUrl/vendors/me/'),
//       headers: headers,
//     );
//     if (res.statusCode == 200) return jsonDecode(res.body);
//     throw Exception('Failed to load profile');
//   }

//   static Future<void> updateLocation({
//     required double latitude,
//     required double longitude,
//   }) async {
//     final headers = await _authHeaders();
//     final res = await http.post(
//       Uri.parse('$kApiBaseUrl/vendors/update-location/'),
//       headers: headers,
//       body: jsonEncode({
//         'latitude': latitude.toStringAsFixed(6),
//         'longitude': longitude.toStringAsFixed(6),
//       }),
//     );
//     if (res.statusCode != 200) {
//       throw Exception('Failed to update location');
//     }
//   }
// }
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/login_screen.dart';
import 'notification_service.dart';
import 'push_service.dart';

class ApiService {
  static const _tokenKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  // ---------- Token storage ----------

  static Future<void> _saveTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> logout() async {
    await PushService.unregisterToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    NotificationService.instance.reset();
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null;
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<bool> _tryRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshKey);
    if (refreshToken == null) return false;

    try {
      final res = await http.post(
        Uri.parse('$kApiBaseUrl/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        await prefs.setString(_tokenKey, data['access']);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> tryRefreshToken() => _tryRefreshToken();

  static Future<void> _forceLogout() async {
    await logout();
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      Navigator.of(ctx).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // ---------- Auth ----------

  static Future<void> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('$kApiBaseUrl/token/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await _saveTokens(data['access'], data['refresh']);
      PushService.registerToken();
    } else {
      throw Exception(
        'Login failed. Please check your username and password with your admin.',
      );
    }
  }

  static String _extractFirstError(dynamic body) {
    if (body is Map) {
      final firstKey = body.keys.first;
      final firstVal = body[firstKey];
      if (firstVal is List && firstVal.isNotEmpty) return '${firstVal.first}';
      return '$firstVal';
    }
    if (body is List && body.isNotEmpty) return '${body.first}';
    return 'Something went wrong. Please try again.';
  }

  // ---------- Vendor profile ----------

  static Future<Map<String, dynamic>> getMyProfile() async {
    var headers = await _authHeaders();
    var res = await http.get(
      Uri.parse('$kApiBaseUrl/vendors/me/'),
      headers: headers,
    );
    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        headers = await _authHeaders();
        res = await http.get(
          Uri.parse('$kApiBaseUrl/vendors/me/'),
          headers: headers,
        );
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your profile.');
  }

  static Future<void> setAvailability(bool isAvailable) async {
    var headers = await _authHeaders();
    var res = await http.patch(
      Uri.parse('$kApiBaseUrl/vendors/me/availability/'),
      headers: headers,
      body: jsonEncode({'is_available': isAvailable}),
    );
    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        headers = await _authHeaders();
        res = await http.patch(
          Uri.parse('$kApiBaseUrl/vendors/me/availability/'),
          headers: headers,
          body: jsonEncode({'is_available': isAvailable}),
        );
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }
    if (res.statusCode != 200) {
      throw Exception('Could not update availability.');
    }
  }

  // ---------- Assigned jobs ----------

  static Future<List<dynamic>> getAssignedJobs() async {
    var headers = await _authHeaders();
    var res = await http.get(
      Uri.parse('$kApiBaseUrl/bookings/assigned/'),
      headers: headers,
    );
    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        headers = await _authHeaders();
        res = await http.get(
          Uri.parse('$kApiBaseUrl/bookings/assigned/'),
          headers: headers,
        );
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your jobs.');
  }

  static Future<void> uploadStartPhoto({
    required int bookingId,
    required File imageFile,
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/bookings/$bookingId/start-photo/');

    Future<http.Response> sendRequest() async {
      final token = await getAccessToken();
      final request = http.MultipartRequest('POST', uri);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields['latitude'] = latitude.toStringAsFixed(6);
      request.fields['longitude'] = longitude.toStringAsFixed(6);
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    }

    var res = await sendRequest();

    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        res = await sendRequest();
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }

    if (res.statusCode != 201) {
      throw Exception(_extractFirstError(jsonDecode(res.body)));
    }
  }

  static Future<void> completeJob(int bookingId) async {
    var headers = await _authHeaders();
    var res = await http.post(
      Uri.parse('$kApiBaseUrl/bookings/$bookingId/complete/'),
      headers: headers,
    );
    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        headers = await _authHeaders();
        res = await http.post(
          Uri.parse('$kApiBaseUrl/bookings/$bookingId/complete/'),
          headers: headers,
        );
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }
    if (res.statusCode != 200) {
      throw Exception(_extractFirstError(jsonDecode(res.body)));
    }
  }

  static Future<Map<String, dynamic>> getVendorProfile() async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$kApiBaseUrl/vendors/me/'),
      headers: headers,
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load profile');
  }

  static Future<void> updateLocation({
    required double latitude,
    required double longitude,
  }) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$kApiBaseUrl/vendors/update-location/'),
      headers: headers,
      body: jsonEncode({
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update location');
    }
  }
}
