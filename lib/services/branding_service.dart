import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Admin-managed logo and wordmark for the vendor app, fetched from the
/// backend and cached on the device so the login screen paints the current
/// branding without waiting on the network.
///
/// This covers the branding *inside* the app only — the launcher icon on the
/// phone's home screen is part of the installed build.
class BrandingService {
  static const _app = 'vendor';
  static const _logoKey = 'branding_logo_url';
  static const _nameKey = 'branding_app_name';
  static const _taglineKey = 'branding_tagline';

  static String? _logoUrl;
  static String? _appName;
  static String? _tagline;

  /// Bumped whenever the branding changes. Screens listen through
  /// [BrandingBuilder] so a logo that arrives after the first frame shows up
  /// straight away, instead of waiting for the next app launch.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Remote logo URL, or null to fall back to the app's built-in icon.
  static String? get logoUrl => _logoUrl;

  /// Admin-set name, or null to keep whatever the screen hardcodes.
  static String? get appName => _appName;
  static String? get tagline => _tagline;

  /// Reads the cached values. Call once before runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _logoUrl = prefs.getString(_logoKey);
      _appName = prefs.getString(_nameKey);
      _tagline = prefs.getString(_taglineKey);
    } catch (_) {}
  }

  /// Pulls the latest branding and caches it. Safe to fire and forget —
  /// nothing here should ever block or break app start-up.
  static Future<void> refresh() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/branding/$_app/'))
          .timeout(const Duration(seconds: 8));

      final prefs = await SharedPreferences.getInstance();

      if (res.statusCode == 404) {
        // Admin cleared the branding — drop back to the built-in icon.
        await prefs.remove(_logoKey);
        await prefs.remove(_nameKey);
        await prefs.remove(_taglineKey);
        _logoUrl = null;
        _appName = null;
        _tagline = null;
        revision.value++;
        return;
      }
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final logo = data['logo'] as String?;
      final name = data['app_name'] as String?;
      final tagline = data['tagline'] as String?;

      if (logo != null && logo.isNotEmpty) {
        await prefs.setString(_logoKey, logo);
        _logoUrl = logo;
      }
      if (name != null && name.isNotEmpty) {
        await prefs.setString(_nameKey, name);
        _appName = name;
      }
      if (tagline != null && tagline.isNotEmpty) {
        await prefs.setString(_taglineKey, tagline);
        _tagline = tagline;
      }
      revision.value++;
    } catch (_) {
      // Offline or backend down — the cached values carry on working.
    }
  }
}
