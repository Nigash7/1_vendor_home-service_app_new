import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/notification_screen.dart';
import 'api_service.dart';
import 'notification_service.dart';

/// Must be top-level and annotated, or Flutter can't find it when the app is
/// killed. The backend sends a `notification` block, so Android draws the tray
/// notification itself — nothing to do here beyond existing.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();

  static bool _initialised = false;

  // -------------------------------------------------------------------- init
  /// Call once from main(), after Firebase.initializeApp().
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestPermission();

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _openFromData(message.data),
    );

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openFromData(initial.data),
      );
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      if (await ApiService.isLoggedIn()) {
        await NotificationService.instance.registerDevice(
          token: token,
          platform: Platform.isIOS ? 'IOS' : 'ANDROID',
        );
      }
    });
  }

  static Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: true,
            sound: true,
          );
    }
  }

  /// iOS only: FCM cannot mint a token until APNs has handed one to the app,
  /// which lands a moment after launch. Calling getToken() before that throws
  /// "APNS token has not been set yet". On Android the token is ready straight
  /// away, which is why this never shows up in Android testing — on iPhone it
  /// meant the device was never registered and no push ever arrived.
  static Future<bool> _apnsReady() async {
    if (!Platform.isIOS) return true;
    for (var attempt = 0; attempt < 10; attempt++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null && apns.isNotEmpty) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('APNs token never arrived - push disabled on this device.');
    return false;
  }

  // ------------------------------------------------------------------ tokens
  /// Call after login, and on startup when already logged in.
  static Future<void> registerToken() async {
    debugPrint('registerToken() called');

    try {
      if (!await ApiService.isLoggedIn()) return;

      if (!await _apnsReady()) return;

      final token = await FirebaseMessaging.instance.getToken();

      if (token == null || token.isEmpty) return;

      await NotificationService.instance.registerDevice(
        token: token,
        platform: Platform.isIOS ? 'IOS' : 'ANDROID',
      );

      debugPrint('FCM token registered: ${token.substring(0, 20)}…');
    } catch (e) {
      debugPrint('FCM token registration skipped: $e');
    }
  }

  /// Call from logout, before the JWT is cleared.
  static Future<void> unregisterToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await NotificationService.instance.unregisterDevice(token);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- handling
  /// A push arrived while the vendor is inside the app. Android draws nothing
  /// in this state, so show a banner they can tap.+
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    NotificationService.instance.refreshUnreadCount();

    final notification = message.notification;
    final context = navigatorKey.currentContext;
    if (notification == null || context == null) return;

    final title = notification.title ?? 'Update';
    final body = notification.body ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _openFromData(message.data),
        ),
      ),
    );
  }

  /// Deep link from a notification tap. Vendor notifications point at jobs.
  static void _openFromData(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    NotificationService.instance.refreshUnreadCount();

    final bookingId = int.tryParse('${data['booking_id'] ?? ''}');
    if (bookingId != null) {
      // TODO: swap in your real screen —
      // Navigator.of(context).push(MaterialPageRoute(
      //   builder: (_) => JobDetailScreen(bookingId: bookingId)));
      // return;
    }

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationScreen()));
  }
}
