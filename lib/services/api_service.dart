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

/// The username and password were right, but the vendor's profile has not
/// been verified by an admin yet — so there is nothing to fix by retyping
/// the password. [verificationStatus] is 'PENDING', 'REJECTED' or null.
class VendorNotApprovedException implements Exception {
  final String? verificationStatus;
  final String message;

  const VendorNotApprovedException(this.verificationStatus, this.message);

  bool get isRejected => verificationStatus == 'REJECTED';

  @override
  String toString() => message;
}

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
      return;
    }

    // The server answers 403 when the credentials are correct but the profile
    // is still awaiting (or was refused) admin verification.
    if (res.statusCode == 403) {
      final data = jsonDecode(res.body);
      throw VendorNotApprovedException(
        data['verification_status'],
        data['detail'] ?? 'Your profile has not been approved yet.',
      );
    }

    throw Exception(
      'Login failed. Please check your username and password.',
    );
  }

  // ---------- Signup ----------

  /// Registers a new vendor. The account is created immediately but stays on
  /// PENDING, so [login] will keep refusing until an admin verifies it.
  static Future<void> signup({
    required String username,
    required String password,
    required String passwordConfirm,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String email,
    required List<int> categoryIds,
    required String serviceArea,
    required String address,
    String? state,
    String? district,
    List<String> serviceStates = const [],
    double? latitude,
    double? longitude,
    required File idProof,
    File? addressProof,
    File? tradeCertificate,
    int? planId,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$kApiBaseUrl/vendors/signup/'),
    );

    request.fields.addAll({
      'username': username,
      'password': password,
      'password_confirm': passwordConfirm,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phoneNumber,
      'email': email,
      'service_area': serviceArea,
      'address': address,
      if (state != null && state.isNotEmpty) 'state': state,
      if (district != null && district.isNotEmpty) 'district': district,
      // A multipart body cannot repeat a field key, so the server accepts the
      // chosen categories as one comma-separated value.
      'categories': categoryIds.join(','),
      // Same trick for the states this vendor will work in. Sending none
      // means every state, which is what the server assumes when the list is
      // left empty.
      if (serviceStates.isNotEmpty) 'service_states': serviceStates.join(','),
      if (latitude != null) 'latitude': latitude.toStringAsFixed(6),
      if (longitude != null) 'longitude': longitude.toStringAsFixed(6),
      // The tier they tapped. Every vendor lands on the free plan regardless;
      // picking anything above it raises a request for an admin to answer.
      if (planId != null) 'plan': '$planId',
    });

    request.files.add(
      await http.MultipartFile.fromPath('id_proof', idProof.path),
    );
    if (addressProof != null) {
      request.files.add(
        await http.MultipartFile.fromPath('address_proof', addressProof.path),
      );
    }
    if (tradeCertificate != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'trade_certificate',
          tradeCertificate.path,
        ),
      );
    }

    final res = await http.Response.fromStream(await request.send());
    if (res.statusCode != 201) {
      // A crash or a proxy answers in HTML, not JSON. Decoding that blindly
      // would surface a parser error instead of something a vendor can act on.
      String message;
      try {
        message = _extractFirstError(jsonDecode(res.body));
      } catch (_) {
        message =
            'The server could not process your application '
            '(error ${res.statusCode}). Please try again later.';
      }
      throw Exception(message);
    }
  }

  /// The service categories a vendor can pick from on the signup form.
  /// Public endpoint — no token needed, since the vendor has no account yet.
  static Future<List<dynamic>> getServiceCategories() async {
    final res = await http.get(Uri.parse('$kApiBaseUrl/services/categories/'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load service categories.');
  }

  /// The states the signup form offers, straight from the server so the
  /// vendor app and the admin dashboard spell them the same way.
  ///
  /// Returns an empty list on failure: not being able to reach the server
  /// must not stop somebody registering, and no states picked simply means
  /// the vendor covers every one until an admin narrows them.
  static Future<List<String>> getStates() async {
    try {
      final res = await http.get(Uri.parse('$kApiBaseUrl/vendors/states/'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return List<String>.from(body['states'] as List<dynamic>);
      }
    } catch (_) {}
    return [];
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

  /// The vendor's own star rating, for the dashboard.
  ///
  /// Best-effort: the dashboard is still perfectly usable without it, so a
  /// failure here returns null rather than taking the whole screen down.
  /// The endpoint is public, but it still goes through [_withAuth] so a
  /// vendor whose token has expired is logged out consistently.
  static Future<Map<String, dynamic>?> getMyRatingSummary(int vendorId) async {
    try {
      final res = await _withAuth(
        (headers) => http.get(
          Uri.parse('$kApiBaseUrl/reviews/vendor/$vendorId/'),
          headers: headers,
        ),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
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

  // ---------- Help & Support ----------
  //
  // The same endpoints the customer app uses. The server works out whether
  // the caller is a vendor or a customer from the token, so nothing here
  // needs to say which app is asking.

  /// Runs [send], and if the token has expired, refreshes it and retries once.
  static Future<http.Response> _withAuth(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var res = await send(await _authHeaders());
    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        res = await send(await _authHeaders());
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }
    return res;
  }

  static Future<List<dynamic>> getMyTickets() async {
    final res = await _withAuth(
      (headers) =>
          http.get(Uri.parse('$kApiBaseUrl/support/my/'), headers: headers),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your support tickets.');
  }

  /// The categories a vendor is allowed to raise a ticket under.
  static Future<List<dynamic>> getTicketCategories() async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/support/categories/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load support categories.');
  }

  static Future<int> createTicket({
    required String subject,
    required String category,
    required String message,
    int? bookingId,
  }) async {
    final body = jsonEncode({
      'subject': subject,
      'category': category,
      'message': message,
      if (bookingId != null) 'booking': bookingId,
    });
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/support/create/'),
        headers: headers,
        body: body,
      ),
    );
    if (res.statusCode == 201) return jsonDecode(res.body)['id'];
    throw Exception(_extractFirstError(jsonDecode(res.body)));
  }

  static Future<Map<String, dynamic>> getTicketDetail(int ticketId) async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/support/$ticketId/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load this ticket.');
  }

  static Future<void> addTicketMessage({
    required int ticketId,
    required String message,
  }) async {
    final body = jsonEncode({'message': message});
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/support/$ticketId/message/'),
        headers: headers,
        body: body,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception('Could not send your message. Please try again.');
    }
  }

  // ---------- Tenders (customer requirements to bid on) ----------
  //
  // Only tenders this vendor's categories cover come back from the server;
  // there is no client-side filtering to get wrong.

  /// Reads the server's error message, falling back to something readable
  /// when the body is HTML from a crash or a proxy rather than JSON.
  static String _errorFrom(http.Response res, String fallback) {
    try {
      return _extractFirstError(jsonDecode(res.body));
    } catch (_) {
      return fallback;
    }
  }

  /// Open tenders this vendor can bid on.
  static Future<List<dynamic>> getOpenTenders({
    int? categoryId,
    String? projectType,
    String? pincode,
    String? district,
  }) async {
    final params = <String, String>{
      if (categoryId != null) 'category': '$categoryId',
      if (projectType != null && projectType.isNotEmpty)
        'project_type': projectType,
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
      if (district != null && district.isNotEmpty) 'district': district,
    };
    final uri = Uri.parse(
      '$kApiBaseUrl/tenders/open/',
    ).replace(queryParameters: params.isEmpty ? null : params);

    final res = await _withAuth((headers) => http.get(uri, headers: headers));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load tenders.');
  }

  static Future<Map<String, dynamic>> getTenderDetail(int tenderId) async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load this tender.');
  }

  /// Every bid this vendor has placed, won or lost.
  static Future<List<dynamic>> getMyBids() async {
    final res = await _withAuth(
      (headers) =>
          http.get(Uri.parse('$kApiBaseUrl/tenders/my-bids/'), headers: headers),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your bids.');
  }

  /// Projects this vendor won and is running.
  static Future<List<dynamic>> getMyTenderProjects() async {
    final res = await _withAuth(
      (headers) =>
          http.get(Uri.parse('$kApiBaseUrl/tenders/awarded/'), headers: headers),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your projects.');
  }

  /// Submits a bid. [milestones] is a list of {title, description, amount}
  /// maps; the server replaces the whole set on every save.
  static Future<Map<String, dynamic>> submitBid({
    required int tenderId,
    required String amount,
    String workPlan = '',
    int? timelineDays,
    String? proposedStartDate,
    String notes = '',
    List<Map<String, dynamic>> milestones = const [],
  }) async {
    final body = jsonEncode({
      'amount': amount,
      'work_plan': workPlan,
      if (timelineDays != null) 'timeline_days': timelineDays,
      if (proposedStartDate != null) 'proposed_start_date': proposedStartDate,
      'notes': notes,
      if (milestones.isNotEmpty) 'milestones': milestones,
    });

    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/bid/'),
        headers: headers,
        body: body,
      ),
    );
    if (res.statusCode == 201) return jsonDecode(res.body);
    throw Exception(_errorFrom(res, 'Could not submit your bid.'));
  }

  /// Revises an existing bid. Leaving [milestones] null keeps the plan the
  /// vendor already submitted; passing an empty list clears it.
  static Future<Map<String, dynamic>> reviseBid({
    required int tenderId,
    required String amount,
    String workPlan = '',
    int? timelineDays,
    String? proposedStartDate,
    String notes = '',
    List<Map<String, dynamic>>? milestones,
  }) async {
    final body = jsonEncode({
      'amount': amount,
      'work_plan': workPlan,
      if (timelineDays != null) 'timeline_days': timelineDays,
      if (proposedStartDate != null) 'proposed_start_date': proposedStartDate,
      'notes': notes,
      if (milestones != null) 'milestones': milestones,
    });

    final res = await _withAuth(
      (headers) => http.patch(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/bid/'),
        headers: headers,
        body: body,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception(_errorFrom(res, 'Could not update your bid.'));
  }

  static Future<void> withdrawBid(int tenderId) async {
    final res = await _withAuth(
      (headers) => http.delete(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/bid/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorFrom(res, 'Could not withdraw your bid.'));
    }
  }

  // ---------- Running an awarded project ----------

  static Future<void> startTenderProject(int tenderId) async {
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/start/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorFrom(res, 'Could not start this project.'));
    }
  }

  static Future<List<dynamic>> getTenderProgress(int tenderId) async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/progress/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load the progress updates.');
  }

  /// Posts an update with any number of photos. Multipart, so it does not go
  /// through [_withAuth] — the files would have to be re-read on the retry.
  static Future<void> postTenderProgress({
    required int tenderId,
    required String message,
    int? percentComplete,
    List<File> images = const [],
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/tenders/$tenderId/progress/add/');

    Future<http.Response> send() async {
      final token = await getAccessToken();
      final request = http.MultipartRequest('POST', uri);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields['message'] = message;
      if (percentComplete != null) {
        request.fields['percent_complete'] = '$percentComplete';
      }
      for (final image in images) {
        request.files.add(
          await http.MultipartFile.fromPath('images', image.path),
        );
      }
      return http.Response.fromStream(await request.send());
    }

    var res = await send();
    if (res.statusCode == 401) {
      if (await _tryRefreshToken()) {
        res = await send();
      } else {
        await _forceLogout();
        throw Exception('Session expired. Please log in again.');
      }
    }
    if (res.statusCode != 201) {
      throw Exception(_errorFrom(res, 'Could not post your update.'));
    }
  }

  /// Marks a stage of work complete, which puts the payment in front of the
  /// customer.
  static Future<void> reachTenderMilestone(int milestoneId) async {
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/tenders/milestones/$milestoneId/reach/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorFrom(res, 'Could not update that milestone.'));
    }
  }

  static Future<void> completeTenderProject(int tenderId) async {
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/tenders/$tenderId/complete/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorFrom(res, 'Could not complete this project.'));
    }
  }

  // ---------- Payout / bank account ----------

  /// The vendor's own payout details.
  ///
  /// Returns `{has_account: bool, account: {...}|null}`. The account number
  /// only ever comes back masked -- the server never sends it in full.
  static Future<Map<String, dynamic>> getBankAccount() async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/vendors/me/bank-account/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your payout details.');
  }

  /// Adds or replaces the payout account.
  ///
  /// [confirmAccountNumber] is checked against [accountNumber] on the server,
  /// so a mistyped digit is caught before it can send money to a stranger.
  static Future<Map<String, dynamic>> saveBankAccount({
    required String accountHolderName,
    required String accountNumber,
    required String confirmAccountNumber,
    required String ifscCode,
    String bankName = '',
    String branchName = '',
    String accountType = 'SAVINGS',
    String upiId = '',
  }) async {
    final res = await _withAuth(
      (headers) => http.put(
        Uri.parse('$kApiBaseUrl/vendors/me/bank-account/'),
        headers: headers,
        body: jsonEncode({
          'account_holder_name': accountHolderName,
          'account_number': accountNumber,
          'confirm_account_number': confirmAccountNumber,
          'ifsc_code': ifscCode,
          'bank_name': bankName,
          'branch_name': branchName,
          'account_type': accountType,
          'upi_id': upiId,
        }),
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception(_errorFrom(res, 'Could not save your payout details.'));
  }

  /// Past changes to the payout account, so a vendor can spot one they did
  /// not make themselves.
  static Future<List<dynamic>> getBankAccountHistory() async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/vendors/me/bank-account/history/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load the change history.');
  }

  // ---------- Subscriptions ----------

  /// The plans on offer. Public, so the signup screen can show them before
  /// the vendor has an account.
  static Future<List<dynamic>> getSubscriptionPlans() async {
    final res = await http.get(Uri.parse('$kApiBaseUrl/subscriptions/plans/'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load the subscription plans.');
  }

  /// Everything the subscription screen shows in one call: the plan the
  /// vendor is on, an upgrade they are waiting on, what else is available,
  /// and the terms they have finished.
  ///
  /// `current` is null when they are on nothing — not an error, and not a
  /// state a vendor who signed up recently will be in.
  static Future<Map<String, dynamic>> getMySubscription() async {
    final res = await _withAuth(
      (headers) => http.get(
        Uri.parse('$kApiBaseUrl/subscriptions/me/'),
        headers: headers,
      ),
    );
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Could not load your plan.');
  }

  /// Asks to be moved to [planId]. This does not change the vendor's plan —
  /// an admin answers it, and approving is what starts the new term.
  static Future<Map<String, dynamic>> requestPlanUpgrade({
    required int planId,
    String note = '',
  }) async {
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/subscriptions/upgrade-requests/'),
        headers: headers,
        body: jsonEncode({'plan': planId, 'note': note}),
      ),
    );
    if (res.statusCode == 201) return jsonDecode(res.body);
    throw Exception(_errorFrom(res, 'Could not send your request.'));
  }

  /// Takes back a request nobody has answered yet.
  static Future<void> withdrawPlanUpgrade(int requestId) async {
    final res = await _withAuth(
      (headers) => http.post(
        Uri.parse(
          '$kApiBaseUrl/subscriptions/upgrade-requests/$requestId/withdraw/',
        ),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorFrom(res, 'Could not withdraw your request.'));
    }
  }
}

