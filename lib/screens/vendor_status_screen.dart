import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dashboard_screen.dart';

/// Shown when a vendor's credentials are correct but their profile is not
/// VERIFIED yet — either freshly submitted, or turned down by an admin.
///
/// The credentials are held only for the lifetime of this screen, so that
/// "Check again" can re-attempt the login without making the vendor retype
/// a password that was already accepted.
class VendorStatusScreen extends StatefulWidget {
  final String username;
  final String password;
  final String? verificationStatus;
  final String message;

  const VendorStatusScreen({
    super.key,
    required this.username,
    required this.password,
    required this.verificationStatus,
    required this.message,
  });

  /// Entry point for a vendor who has just submitted the signup form and has
  /// no reason to re-check anything yet.
  const VendorStatusScreen.justSubmitted({
    super.key,
    required this.username,
    required this.message,
  }) : password = '',
       verificationStatus = 'PENDING';

  @override
  State<VendorStatusScreen> createState() => _VendorStatusScreenState();
}

class _VendorStatusScreenState extends State<VendorStatusScreen> {
  late String? _status = widget.verificationStatus;
  late String _message = widget.message;
  bool _isChecking = false;

  bool get _isRejected => _status == 'REJECTED';
  bool get _canRecheck => widget.password.isNotEmpty && !_isRejected;

  Future<void> _checkAgain() async {
    setState(() => _isChecking = true);
    try {
      await ApiService.login(widget.username, widget.password);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
    } on VendorNotApprovedException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.verificationStatus;
        _message = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _isRejected ? Colors.red.shade700 : Colors.deepOrange;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          _isRejected
                              ? Icons.cancel_outlined
                              : Icons.hourglass_top_rounded,
                          size: 64,
                          color: accent,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isRejected
                              ? 'Application not approved'
                              : 'Waiting for admin approval',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.grey.shade900
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_canRecheck)
                          SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _isChecking ? null : _checkAgain,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _isChecking
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: const Text('Check again'),
                            ),
                          ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to login'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
