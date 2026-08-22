import 'package:flutter/material.dart';

import '../services/branding_service.dart';

/// Rebuilds its subtree whenever the branding lands from the backend, so a
/// screen already on-screen picks up the new logo or name without a restart.
class BrandingBuilder extends StatelessWidget {
  final WidgetBuilder builder;

  const BrandingBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BrandingService.revision,
      builder: (context, _, __) => builder(context),
    );
  }
}

/// The vendor app's logo. Shows whatever the admin uploaded, falling back to
/// the built-in engineering icon when nothing is set, the image fails to
/// load, or the device is offline before its first successful fetch.
class AppLogo extends StatelessWidget {
  final double size;

  /// Clips the logo into a circle to match the login screen's avatar. The
  /// splash shows it uncropped, since a wide wordmark would lose its edges.
  final bool circular;

  const AppLogo({super.key, this.size = 56, this.circular = true});

  @override
  Widget build(BuildContext context) {
    return BrandingBuilder(
      builder: (context) {
        final url = BrandingService.logoUrl;

        if (url == null || url.isEmpty) return _fallback();

        final image = Image.network(
          url,
          width: size + 32,
          height: size + 32,
          fit: circular ? BoxFit.cover : BoxFit.contain,
          errorBuilder: (_, __, ___) => _fallback(),
          frameBuilder: (context, child, frame, wasSynchronous) {
            if (wasSynchronous || frame != null) return child;
            return _fallback();
          },
        );

        return circular ? ClipOval(child: image) : image;
      },
    );
  }

  Widget _fallback() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.engineering, size: size, color: Colors.deepOrange),
    );
  }
}
