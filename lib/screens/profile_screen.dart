import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'bank_account_screen.dart';
import 'location_settings_screen.dart';
import 'login_screen.dart';
import 'subscription_screen.dart';
import 'support_screen.dart';

/// The vendor's own profile: identity, verification state, the work they are
/// approved for, and the switches they control themselves.
///
/// Everything here except availability is set by the admin — the vendor can
/// see it but not change it, which mirrors what the API allows.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSavingAvailability = false;
  String? _errorMessage;

  // Loaded separately from the profile: payout details are their own
  // endpoint, and a failure there must not blank the whole screen.
  Map<String, dynamic>? _bankAccount;
  bool _hasBankAccount = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final profile = await ApiService.getMyProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
      await _loadBankAccount();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  /// Best-effort — the profile is still usable if this fails, so a payout
  /// lookup that errors just leaves the card in its "not added" state.
  Future<void> _loadBankAccount() async {
    try {
      final data = await ApiService.getBankAccount();
      if (!mounted) return;
      setState(() {
        _hasBankAccount = data['has_account'] == true;
        _bankAccount = _hasBankAccount
            ? Map<String, dynamic>.from(data['account'])
            : null;
      });
    } catch (_) {
      if (mounted) setState(() => _hasBankAccount = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    final previous = _profile?['is_available'] == true;
    setState(() {
      _profile?['is_available'] = value;
      _isSavingAvailability = true;
    });

    try {
      await ApiService.setAvailability(value);
      if (!mounted) return;
      _snack(
        value
            ? 'You are now available for new jobs.'
            : 'You will not be given new jobs.',
      );
    } catch (e) {
      if (!mounted) return;
      // Put the switch back where it was — the server is the source of truth.
      setState(() => _profile?['is_available'] = previous);
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSavingAvailability = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need your username and password to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ApiService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ derived
  String get _fullName {
    final first = '${_profile?['first_name'] ?? ''}'.trim();
    final last = '${_profile?['last_name'] ?? ''}'.trim();
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? '${_profile?['username'] ?? 'Vendor'}' : name;
  }

  String get _initials {
    final parts = _fullName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool get _hasWorkLocation =>
      _profile?['latitude'] != null && _profile?['longitude'] != null;

  List<dynamic> get _categories =>
      (_profile?['categories'] as List<dynamic>?) ?? const [];

  // -------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildAvailabilityCard(),
                  const SizedBox(height: 16),
                  _buildSection('Contact', [
                    _row(Icons.phone_outlined, 'Phone',
                        '${_profile?['phone_number'] ?? ''}'),
                    _row(Icons.email_outlined, 'Email',
                        '${_profile?['email'] ?? ''}'),
                    _row(Icons.person_outline, 'Username',
                        '${_profile?['username'] ?? ''}'),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection('Work Details', [
                    _row(Icons.map_outlined, 'Service area',
                        '${_profile?['service_area'] ?? ''}'),
                    _row(Icons.location_city_outlined, 'Based in',
                        _basedIn()),
                    // Set by an admin, so it is shown rather than edited.
                    // Nothing listed means this vendor is offered everywhere,
                    // which is worth saying out loud.
                    _row(Icons.public_outlined, 'Where you serve',
                        _servedRegions(), maxLines: 4),
                    _row(Icons.home_outlined, 'Address',
                        '${_profile?['address'] ?? ''}', maxLines: 3),
                  ]),
                  const SizedBox(height: 16),
                  _buildSkillsCard(),
                  const SizedBox(height: 16),
                  _buildSubscriptionCard(),
                  const SizedBox(height: 16),
                  _buildBankAccountCard(),
                  const SizedBox(height: 16),
                  _buildLocationCard(),
                  const SizedBox(height: 16),
                  _buildSupportCard(),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Log Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Contact your admin to change any detail above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadProfile, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final status = '${_profile?['verification_status'] ?? 'PENDING'}';

    return _card(
      child: Row(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.deepOrange.withValues(alpha: 0.12),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Vendor ID #${_profile?['id'] ?? '-'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                _verificationBadge(status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _verificationBadge(String status) {
    late final Color color;
    late final IconData icon;
    late final String label;

    switch (status) {
      case 'VERIFIED':
        color = Colors.green.shade700;
        icon = Icons.verified;
        label = 'Verified';
      case 'REJECTED':
        color = Colors.red.shade600;
        icon = Icons.gpp_bad_outlined;
        label = 'Not verified';
      default:
        color = Colors.orange.shade800;
        icon = Icons.pending_outlined;
        label = 'Pending review';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    final isAvailable = _profile?['is_available'] == true;

    return _card(
      child: Row(
        children: [
          Icon(
            isAvailable ? Icons.work_outline : Icons.work_off_outlined,
            color: isAvailable ? Colors.green.shade700 : Colors.grey,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available for work',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  isAvailable
                      ? 'You can be assigned new jobs.'
                      : 'Turn this on when you are back on duty.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (_isSavingAvailability)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: isAvailable,
              activeThumbColor: Colors.deepOrange,
              onChanged: _toggleAvailability,
            ),
        ],
      ),
    );
  }

  Widget _buildSkillsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Approved Services',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Jobs in these categories can be assigned to you.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          if (_categories.isEmpty)
            Text(
              'No categories assigned yet. Your admin sets these.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.deepOrange.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    '${c['name'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// The plan the vendor is on, and the way through to the upgrade options.
  ///
  /// Ships inside the profile payload, so this costs no extra call. Every
  /// vendor lands on the free tier at signup, but a vendor from before plans
  /// existed can still be on nothing until the admin backfills them.
  Widget _buildSubscriptionCard() {
    final plan = _profile?['subscription'] as Map<String, dynamic>?;
    final expiringSoon = plan?['is_expiring_soon'] == true;
    final daysLeft = plan?['days_remaining'] as int?;

    late final String subtitle;
    if (plan == null) {
      subtitle = 'Not on a plan yet. Tap to see what is available.';
    } else if (plan['end_date'] == null) {
      subtitle = plan['is_free'] == true
          ? 'Free plan · no expiry. Tap to see upgrade options.'
          : '₹${plan['price']} · no expiry. Tap to see other plans.';
    } else {
      subtitle =
          'Renews ${plan['end_date']}'
          '${daysLeft != null ? ' · $daysLeft day${daysLeft == 1 ? '' : 's'} left' : ''}';
    }

    return _card(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          plan == null ? Icons.workspace_premium_outlined : Icons.workspace_premium,
          color: plan == null
              ? Colors.grey
              : (expiringSoon ? Colors.orange : Colors.deepOrange),
        ),
        title: Row(
          children: [
            Text(
              plan == null ? 'My Plan' : '${plan['plan_name']} plan',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (plan?['is_free'] == true) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Free',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: expiringSoon ? Colors.orange.shade800 : Colors.grey.shade600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
          );
          // They may have asked for a different plan while they were in there.
          _loadProfile();
        },
      ),
    );
  }

  Widget _buildBankAccountCard() {
    final isVerified = _bankAccount?['is_verified'] == true;
    final masked = '${_bankAccount?['account_number'] ?? ''}';

    return _card(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          _hasBankAccount ? Icons.account_balance : Icons.account_balance_outlined,
          color: _hasBankAccount
              ? (isVerified ? Colors.green.shade700 : Colors.orange)
              : Colors.red.shade600,
        ),
        title: const Text(
          'Payout Account',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          !_hasBankAccount
              ? 'Not added. We cannot send your earnings without it.'
              : isVerified
                  ? 'Verified — $masked'
                  : '$masked — we are checking these details.',
          style: TextStyle(
            fontSize: 12,
            color: _hasBankAccount ? Colors.grey.shade600 : Colors.red.shade600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BankAccountScreen()),
          );
          // They may have added or changed the account while in there.
          _loadBankAccount();
        },
      ),
    );
  }

  Widget _buildLocationCard() {
    return _card(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          _hasWorkLocation ? Icons.location_on : Icons.location_off_outlined,
          color: _hasWorkLocation ? Colors.green.shade700 : Colors.orange,
        ),
        title: const Text(
          'Work Location',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _hasWorkLocation
              ? 'Set — used to match you with nearby jobs.'
              : 'Not set. Tap to capture your GPS location.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LocationSettingsScreen()),
          );
          // The vendor may have saved a new pin while they were in there.
          _loadProfile();
        },
      ),
    );
  }

  Widget _buildSupportCard() {
    return _card(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: const Icon(Icons.support_agent, color: Colors.deepOrange),
        title: const Text(
          'Help & Support',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Raise a ticket about a job, payout or your account.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportScreen()),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ helpers
  /// "Ernakulam, Kerala", or an empty string when neither is on file.
  String _basedIn() {
    final parts = [
      '${_profile?['district'] ?? ''}'.trim(),
      '${_profile?['state'] ?? ''}'.trim(),
    ].where((p) => p.isNotEmpty);
    return parts.join(', ');
  }

  /// "Kerala — Ernakulam, Thrissur", one entry per state, or all of them.
  String _servedRegions() {
    final regions = (_profile?['service_regions'] as List<dynamic>?) ?? [];
    return regions.isEmpty ? 'All states' : regions.join('  •  ');
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDF2)),
      ),
      child: child,
    );
  }

  Widget _row(IconData icon, String label, String value, {int maxLines = 1}) {
    final display = value.trim().isEmpty ? 'Not provided' : value.trim();
    final isMissing = value.trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  display,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.3,
                    color: isMissing ? Colors.grey : Colors.black87,
                    fontStyle: isMissing ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
