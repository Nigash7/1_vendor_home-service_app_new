import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/branding_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/notification_bell.dart';
import 'job_detail_screen.dart';
import 'jobs_list_screen.dart';
import 'location_settings_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';
import 'tenders_screen.dart';

/// The vendor app's accent, matching the login, jobs list and job detail
/// screens. Literal rather than `colorScheme.primary`, because the Material 3
/// scheme generated from the deepOrange seed comes out noticeably muted.
const Color _accent = Colors.deepOrange;
const Color _bg = Color(0xFFF6F6F8);
const Color _border = Color(0xFFEDEDF2);

/// One day's completed-job count, for the week strip.
class _DayCount {
  final DateTime day;
  final int count;

  const _DayCount(this.day, this.count);
}

/// The vendor's landing screen.
///
/// Everything here is worked out from the two calls the app already makes —
/// `/vendors/me/` and `/bookings/assigned/` — plus the rating summary. A
/// vendor's job list is small enough that totalling it on the device is
/// cheaper than a round trip to a dedicated stats endpoint, and it keeps these
/// numbers in step with what the Jobs screen shows.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _profile;
  List<dynamic> _jobs = [];
  Map<String, dynamic>? _rating;

  bool _isLoading = true;
  bool _isSavingAvailability = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _errorMessage = null);

    try {
      final profile = await ApiService.getMyProfile();
      final jobs = await ApiService.getAssignedJobs();

      // Best-effort: the rest of the dashboard stands on its own without it.
      final vendorId = profile['id'];
      final rating = vendorId is int
          ? await ApiService.getMyRatingSummary(vendorId)
          : null;

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _jobs = jobs;
        _rating = rating ?? _rating;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
      // A failed pull-to-refresh keeps the numbers already on screen and says
      // why in a snack bar, rather than blanking a working dashboard.
      if (_profile != null) _snack(message);
    }
  }

  /// Asks before a vendor goes off duty.
  ///
  /// Only in that direction: the switch sits on the landing screen where an
  /// accidental tap is easy, and going off duty quietly stops new work
  /// reaching them. Coming back on has no such cost, so it stays instant.
  Future<bool> _confirmGoingOffDuty() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Go off duty?'),
        content: const Text(
          'You will not be given any new jobs until you turn this back on. '
          'Jobs already assigned to you stay yours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay available'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Go off duty',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _toggleAvailability(bool value) async {
    // Confirm before anything moves — the Switch is fully controlled, so it
    // sits where it was until the state below changes, and a cancelled
    // dialog leaves it on without a flicker.
    if (!value) {
      final confirmed = await _confirmGoingOffDuty();
      if (!confirmed || !mounted) return;
    }

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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pushes [screen] and refreshes on the way back — a job started, a location
  /// pinned or availability changed elsewhere all move numbers on this screen.
  Future<void> _openThenReload(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  // ----------------------------------------------------------------- derived
  static const _activeStatuses = ['ASSIGNED', 'IN_PROGRESS'];

  List<Map<String, dynamic>> get _allJobs =>
      _jobs.map((j) => Map<String, dynamic>.from(j)).toList();

  List<Map<String, dynamic>> get _activeJobs =>
      _allJobs.where((j) => _activeStatuses.contains(j['status'])).toList();

  List<Map<String, dynamic>> get _completedJobs =>
      _allJobs.where((j) => j['status'] == 'COMPLETED').toList();

  /// Active jobs scheduled for today, earliest first — the vendor's actual
  /// running order for the day.
  List<Map<String, dynamic>> get _todayJobs {
    final today = _dateOnly(DateTime.now());
    final jobs = _activeJobs.where((j) {
      final date = _parseDate(j['preferred_date']);
      return date != null && _dateOnly(date) == today;
    }).toList();

    jobs.sort(
      (a, b) => '${a['preferred_time']}'.compareTo('${b['preferred_time']}'),
    );
    return jobs;
  }

  /// The next active job after today, so a vendor with a clear day still knows
  /// what is coming.
  Map<String, dynamic>? get _nextJob {
    final today = _dateOnly(DateTime.now());
    final upcoming = _activeJobs.where((j) {
      final date = _parseDate(j['preferred_date']);
      return date != null && _dateOnly(date).isAfter(today);
    }).toList();

    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) {
      final da = '${a['preferred_date']} ${a['preferred_time']}';
      final db = '${b['preferred_date']} ${b['preferred_time']}';
      return da.compareTo(db);
    });
    return upcoming.first;
  }

  /// Still open, but the scheduled day has already passed.
  List<Map<String, dynamic>> get _overdueJobs {
    final today = _dateOnly(DateTime.now());
    return _activeJobs.where((j) {
      final date = _parseDate(j['preferred_date']);
      return date != null && _dateOnly(date).isBefore(today);
    }).toList();
  }

  /// When a job counts as finished. `completed_at` is the truth; jobs closed
  /// before that field was being filled fall back to their scheduled date.
  DateTime? _finishedOn(Map<String, dynamic> job) {
    final completedAt = DateTime.tryParse('${job['completed_at'] ?? ''}');
    if (completedAt != null) return completedAt.toLocal();
    return _parseDate(job['preferred_date']);
  }

  List<Map<String, dynamic>> get _completedThisMonth {
    final now = DateTime.now();
    return _completedJobs.where((j) {
      final done = _finishedOn(j);
      return done != null && done.year == now.year && done.month == now.month;
    }).toList();
  }

  double get _valueThisMonth => _completedThisMonth.fold<double>(
    0,
    (sum, j) => sum + (double.tryParse('${j['amount'] ?? 0}') ?? 0),
  );

  /// Work that is done or under way but not yet marked paid — the figure a
  /// vendor is chasing.
  double get _pendingPayment => _allJobs
      .where(
        (j) =>
            j['status'] != 'CANCELLED' &&
            j['status'] != 'PENDING' &&
            j['payment_status'] != 'PAID',
      )
      .fold<double>(
        0,
        (sum, j) => sum + (double.tryParse('${j['amount'] ?? 0}') ?? 0),
      );

  /// Completed jobs per day for the last seven days, oldest first.
  List<_DayCount> get _lastSevenDays {
    final today = _dateOnly(DateTime.now());
    return List.generate(7, (i) {
      // Built by day-of-month arithmetic rather than subtracting a Duration,
      // so every bar lands on local midnight and today's bar always matches.
      final day = DateTime(today.year, today.month, today.day - (6 - i));
      final count = _completedJobs.where((j) {
        final done = _finishedOn(j);
        return done != null && _dateOnly(done) == day;
      }).length;
      return _DayCount(day, count);
    });
  }

  String get _fullName {
    final first = '${_profile?['first_name'] ?? ''}'.trim();
    final last = '${_profile?['last_name'] ?? ''}'.trim();
    final name = [first, last].where((s) => s.isNotEmpty).join(' ');
    return name.isEmpty ? '${_profile?['username'] ?? 'Vendor'}' : name;
  }

  String get _firstName => _fullName.split(' ').first;

  String get _initials {
    final parts = _fullName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool get _hasWorkLocation =>
      _profile?['latitude'] != null && _profile?['longitude'] != null;

  // -------------------------------------------------------------- formatting
  static const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime? _parseDate(dynamic raw) => DateTime.tryParse('${raw ?? ''}'.trim());

  /// '10:30:00' -> '10:30 AM'. Hand-rolled because the vendor app doesn't
  /// depend on intl; falls back to the raw value if the backend surprises us.
  String _time(dynamic raw) {
    final text = '${raw ?? ''}'.trim();
    final parsed = DateTime.tryParse('1970-01-01 $text');
    if (parsed == null) return text;

    final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${parsed.hour < 12 ? 'AM' : 'PM'}';
  }

  String _shortDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

  /// Indian grouping — 12,34,567 rather than 1,234,567. Paise are dropped;
  /// prices here are whole rupees and the tiles are tight on space.
  String _amount(num value) {
    var text = value.round().abs().toString();
    if (text.length > 3) {
      final head = text.substring(0, text.length - 3);
      final tail = text.substring(text.length - 3);
      final grouped = head.replaceAllMapped(
        RegExp(r'(\d)(?=(\d\d)+$)'),
        (m) => '${m[1]},',
      );
      text = '$grouped,$tail';
    }
    return '₹$text';
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'My Profile',
            onPressed: () => _openThenReload(const ProfileScreen()),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          // A refresh that fails keeps the numbers already on screen and shows
          // the reason in a snack bar instead of blanking the dashboard.
          : _errorMessage != null && _profile == null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _greetingCard(),
                  ..._alerts(),
                  const SizedBox(height: 16),
                  _statRow(),
                  const SizedBox(height: 16),
                  _monthCard(),
                  const SizedBox(height: 16),
                  _todaySection(),
                  const SizedBox(height: 16),
                  _quickActions(),
                ],
              ),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withValues(alpha: 0.08),
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: _accent,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Couldn't load your dashboard",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ header
  Widget _greetingCard() {
    final isAvailable = _profile?['is_available'] == true;

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => _openThenReload(const ProfileScreen()),
                child: Container(
                  height: 54,
                  width: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent.withValues(alpha: 0.12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: _accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    BrandingBuilder(
                      builder: (context) => Text(
                        BrandingService.appName ?? 'Vendor Partner',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 6),

          // The one control a vendor reaches for most, so it sits above the
          // fold instead of a screen deeper in the profile.
          Row(
            children: [
              Icon(
                isAvailable ? Icons.work_outline : Icons.work_off_outlined,
                size: 20,
                color: isAvailable ? Colors.green.shade700 : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Available for work',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAvailable
                          ? 'You can be assigned new jobs.'
                          : 'Turn this on when you are back on duty.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
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
                  activeThumbColor: _accent,
                  onChanged: _toggleAvailability,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ alerts
  /// Things that need the vendor to do something. Nothing shows when the
  /// account is in good shape, which is the normal case.
  List<Widget> _alerts() {
    final alerts = <Widget>[];
    final status = '${_profile?['verification_status'] ?? 'PENDING'}';
    final overdue = _overdueJobs.length;

    if (overdue > 0) {
      alerts.add(
        _alert(
          icon: Icons.schedule,
          color: Colors.red.shade600,
          title: overdue == 1
              ? '1 job is overdue'
              : '$overdue jobs are overdue',
          message: 'Their scheduled time has passed and they are still open.',
          onTap: () => _openThenReload(const JobsListScreen()),
        ),
      );
    }

    if (status != 'VERIFIED') {
      alerts.add(
        _alert(
          icon: status == 'REJECTED'
              ? Icons.gpp_bad_outlined
              : Icons.pending_outlined,
          color: status == 'REJECTED'
              ? Colors.red.shade600
              : Colors.orange.shade800,
          title: status == 'REJECTED'
              ? 'Your account is not verified'
              : 'Verification pending',
          message:
              'Your admin reviews this. Raise a ticket if it is taking long.',
          onTap: () => _openThenReload(const SupportScreen()),
        ),
      );
    }

    if (!_hasWorkLocation) {
      alerts.add(
        _alert(
          icon: Icons.location_off_outlined,
          color: Colors.orange.shade800,
          title: 'Work location not set',
          message: 'Set it so you get matched with jobs near you.',
          onTap: () => _openThenReload(const LocationSettingsScreen()),
        ),
      );
    }

    return alerts;
  }

  Widget _alert({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- stats
  Widget _statRow() {
    final average = _rating?['average_rating'];
    final totalReviews = _rating?['total_reviews'] ?? 0;
    final hasRating = average != null && '$average' != '0';

    return Row(
      children: [
        Expanded(
          child: _statTile(
            icon: Icons.handyman_outlined,
            color: Colors.purple.shade600,
            value: '${_activeJobs.length}',
            label: 'Active jobs',
            onTap: () => _openThenReload(const JobsListScreen()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(
            icon: Icons.today_outlined,
            color: Colors.blue.shade700,
            value: '${_todayJobs.length}',
            label: 'Due today',
            onTap: () => _openThenReload(const JobsListScreen()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(
            icon: hasRating ? Icons.star_rounded : Icons.star_outline_rounded,
            color: Colors.amber.shade700,
            value: hasRating ? '$average' : '—',
            label: hasRating
                ? (totalReviews == 1 ? '1 review' : '$totalReviews reviews')
                : 'No reviews yet',
          ),
        ),
      ],
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.25,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: content,
      ),
    );
  }

  // -------------------------------------------------------------- this month
  Widget _monthCard() {
    final now = DateTime.now();
    final done = _completedThisMonth.length;
    final pending = _pendingPayment;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'This month',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_months[now.month - 1]} ${now.year}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Completed job value',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      child: Text(
                        _amount(_valueThisMonth),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade700.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '$done',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade700,
                      ),
                    ),
                    Text(
                      done == 1 ? 'job done' : 'jobs done',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (pending > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_amount(pending)} still marked unpaid across your jobs',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),
          const Divider(height: 1, color: _border),
          const SizedBox(height: 14),

          Text(
            'Jobs completed · last 7 days',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          _weekChart(),
        ],
      ),
    );
  }

  /// A plain seven-bar strip. Hand-drawn with containers rather than pulling a
  /// charting package into the app for one small widget.
  ///
  /// Height is deliberately left to the content: each column sizes to its own
  /// bar and the row bottom-aligns them, so the bars still share a baseline
  /// while nothing can overflow — a fixed box here clipped the tallest bar
  /// once the two labels were added, and would break again on a phone set to
  /// a larger text size.
  Widget _weekChart() {
    final days = _lastSevenDays;
    final peak = days.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final today = _dateOnly(DateTime.now());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: days.map((day) {
        final isToday = day.day == today;
        // Empty days keep a 4px stub so the week still reads as a row.
        final height = peak == 0 ? 4.0 : 4 + (day.count / peak) * 44;

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Zero days keep a muted '0' rather than an empty string, so
              // every column has the same label row and the bars line up.
              Text(
                '${day.count}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: day.count == 0
                      ? Colors.grey.shade400
                      : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: day.count == 0
                      ? _border
                      : _accent.withValues(alpha: isToday ? 1 : 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _weekdayInitials[day.day.weekday - 1],
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  color: isToday ? _accent : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ------------------------------------------------------------------- today
  Widget _todaySection() {
    final todayJobs = _todayJobs;
    final next = _nextJob;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Today's schedule",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_activeJobs.isNotEmpty)
                TextButton(
                  onPressed: () => _openThenReload(const JobsListScreen()),
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (todayJobs.isNotEmpty)
            ...todayJobs.map(_jobRow)
          else ...[
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nothing scheduled for today.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 16),
              Text(
                'Next up · ${_shortDate(_parseDate(next['preferred_date'])!)}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              _jobRow(next),
            ],
          ],
        ],
      ),
    );
  }

  Widget _jobRow(Map<String, dynamic> job) {
    final inProgress = job['status'] == 'IN_PROGRESS';
    final address = '${job['address_text'] ?? ''}'.trim();
    final time = _time(job['preferred_time']).split(' ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openThenReload(JobDetailScreen(job: job)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    children: [
                      Text(
                        time.first,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      if (time.length > 1)
                        Text(
                          time.last,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${job['category_name'] ?? 'Job'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (inProgress) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade600.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'On job',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.purple.shade600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        address.isEmpty
                            ? '${job['customer_name'] ?? 'Customer'}'
                            : '${job['customer_name'] ?? 'Customer'} · $address',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- quick actions
  Widget _quickActions() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick actions',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _action(
                  Icons.work_outline,
                  'My Jobs',
                  () => _openThenReload(const JobsListScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _action(
                  Icons.notifications_none_rounded,
                  'Notifications',
                  () => _openThenReload(const NotificationScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _action(
                  Icons.gavel_rounded,
                  'Tenders',
                  () => _openThenReload(const TendersScreen()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _action(
                  Icons.location_on_outlined,
                  'Work Location',
                  () => _openThenReload(const LocationSettingsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _action(
                  Icons.support_agent,
                  'Help & Support',
                  () => _openThenReload(const SupportScreen()),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: _bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 19, color: _accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- helpers
  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }
}
