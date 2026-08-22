import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/api_service.dart';
import 'services/branding_service.dart';
import 'services/push_service.dart';
import 'screens/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushService.init();

  // Cached branding first so the login screen paints the right logo
  // immediately, then refresh in the background for the next launch.
  await BrandingService.load();
  BrandingService.refresh();

  // Already signed in from a previous session? Refresh the device token.
  if (await ApiService.isLoggedIn()) {
    PushService.registerToken();
  }

  runApp(const VendorApp());
}

class VendorApp extends StatelessWidget {
  const VendorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Service - Vendor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
    );
  }
}
