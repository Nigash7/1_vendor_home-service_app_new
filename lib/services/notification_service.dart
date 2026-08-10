import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/app_notification.dart';
import 'api_service.dart';

/// Singleton notification client, matching the CartService pattern.
///
/// Uses kApiBaseUrl and ApiService's token handling, so there is nothing to
/// configure here — change your base URL in config.dart as usual.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Badge count. Wrap any bell in a ValueListenableBuilder on this and every
  /// copy of it updates at once — no state management package needed.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  // ------------------------------------------------------------------ plumbing
  Future<Map<String, String>> _authHeaders() async {
    final token = await ApiService.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Runs a request, and retries once with a fresh token on 401 —
  /// same pattern as the rest of ApiService.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    var headers = await _authHeaders();
    var res = await request(headers);
    if (res.statusCode == 401 && await ApiService.tryRefreshToken()) {
      headers = await _authHeaders();
      res = await request(headers);
    }
    return res;
  }

  Never _fail(http.Response res) {
    String detail = 'Request failed (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] != null) {
        detail = body['detail'].toString();
      }
    } catch (_) {}
    throw Exception(detail);
  }

  // ---------------------------------------------------------------------- read
  /// GET /api/notifications/
  Future<NotificationPage> fetch({
    int page = 1,
    bool unreadOnly = false,
    String? category,
  }) async {
    final uri = Uri.parse('$kApiBaseUrl/notifications/').replace(
      queryParameters: {
        'page': '$page',
        if (unreadOnly) 'unread': 'true',
        if (category != null) 'category': category,
      },
    );

    final res = await _send((headers) => http.get(uri, headers: headers));
    if (res.statusCode != 200) _fail(res);

    final result = NotificationPage.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
    unreadCount.value = result.unreadCount;
    return result;
  }

  /// GET /api/notifications/unread-count/ — cheap, safe to call often.
  Future<int> refreshUnreadCount() async {
    try {
      final res = await _send(
        (headers) => http.get(
          Uri.parse('$kApiBaseUrl/notifications/unread-count/'),
          headers: headers,
        ),
      );
      if (res.statusCode != 200) return unreadCount.value;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      unreadCount.value = body['unread_count'] as int? ?? 0;
    } catch (_) {
      // The badge is cosmetic — never surface a network error for it.
    }
    return unreadCount.value;
  }

  // --------------------------------------------------------------------- write
  /// POST /api/notifications/<id>/read/
  Future<void> markRead(int id) async {
    final res = await _send(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/notifications/$id/read/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) _fail(res);
    if (unreadCount.value > 0) unreadCount.value = unreadCount.value - 1;
  }

  /// POST /api/notifications/read-all/
  Future<void> markAllRead() async {
    final res = await _send(
      (headers) => http.post(
        Uri.parse('$kApiBaseUrl/notifications/read-all/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) _fail(res);
    unreadCount.value = 0;
  }

  /// DELETE /api/notifications/<id>/
  Future<void> delete(int id) async {
    final res = await _send(
      (headers) => http.delete(
        Uri.parse('$kApiBaseUrl/notifications/$id/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) _fail(res);
    await refreshUnreadCount();
  }

  /// DELETE /api/notifications/clear/
  Future<void> clearAll() async {
    final res = await _send(
      (headers) => http.delete(
        Uri.parse('$kApiBaseUrl/notifications/clear/'),
        headers: headers,
      ),
    );
    if (res.statusCode != 200) _fail(res);
    unreadCount.value = 0;
  }

  // ------------------------------------------------------------ device tokens
  /// POST /api/notifications/devices/ — call once FCM hands you a token.
  /// Safe to call on every app start; the backend upserts on the token value.
  Future<void> registerDevice({
    required String token,
    String platform = 'ANDROID',
    String deviceId = '',
    String appVersion = '',
  }) async {
    try {
      await _send(
        (headers) => http.post(
          Uri.parse('$kApiBaseUrl/notifications/devices/'),
          headers: headers,
          body: jsonEncode({
            'token': token,
            'platform': platform,
            'device_id': deviceId,
            'app_version': appVersion,
          }),
        ),
      );
    } catch (_) {
      // Never block startup on token registration.
    }
  }

  /// DELETE /api/notifications/devices/ — call on logout so the user stops
  /// receiving pushes on a device they've signed out of.
  Future<void> unregisterDevice(String token) async {
    try {
      await _send(
        (headers) => http.delete(
          Uri.parse('$kApiBaseUrl/notifications/devices/'),
          headers: headers,
          body: jsonEncode({'token': token}),
        ),
      );
    } catch (_) {}
  }

  /// Called from ApiService.logout().
  void reset() => unreadCount.value = 0;
}
