import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/branding_service.dart';
import '../widgets/app_logo.dart';
import 'dashboard_screen.dart';
import 'login_screen.dart';

/// Vendor splash. Also the only place a vendor who stays signed in ever sees
/// the branding, since they skip the login screen entirely.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnimation = Tween<double>(
      begin: 0.85,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();
    _openNextScreen();
  }

  Future<void> _openNextScreen() async {
    // Long enough for the branding fetch to land, so the logo is on screen
    // rather than flashing past.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final loggedIn = await ApiService.isLoggedIn();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            loggedIn ? const DashboardScreen() : const LoginScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: BrandingBuilder(
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 180, circular: false),
                  const SizedBox(height: 24),
                  Text(
                    BrandingService.appName ?? 'Vendor',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange.shade800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    BrandingService.tagline ?? 'Your jobs, all in one place',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
