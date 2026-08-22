import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'job_detail_screen.dart';
import 'profile_screen.dart';
import '../widgets/notification_bell.dart';

/// How one job status is presented on a card.
class _StatusStyle {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusStyle(this.label, this.color, this.icon);
}

class JobsListScreen extends StatefulWidget {
  const JobsListScreen({super.key});

  @override
  State<JobsListScreen> createState() => _JobsListScreenState();
}

class _JobsListScreenState extends State<JobsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _jobs = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const _bg = Color(0xFFF6F6F8);
  static const _border = Color(0xFFEDEDF2);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadJobs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final jobs = await ApiService.getAssignedJobs();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  // Active = assigned or in progress
  List<dynamic> get _activeJobs => _jobs
      .where((j) => j['status'] == 'ASSIGNED' || j['status'] == 'IN_PROGRESS')
      .toList();

  // Completed jobs
  List<dynamic> get _completedJobs =>
      _jobs.where((j) => j['status'] == 'COMPLETED').toList();

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'ASSIGNED':
        return _StatusStyle(
          'Assigned',
          Colors.blue.shade700,
          Icons.assignment_outlined,
        );
      case 'IN_PROGRESS':
        return _StatusStyle(
          'In Progress',
          Colors.purple.shade600,
          Icons.handyman_outlined,
        );
      case 'COMPLETED':
        return _StatusStyle(
          'Completed',
          Colors.green.shade700,
          Icons.check_circle_outline,
        );
      case 'CANCELLED':
        return _StatusStyle(
          'Cancelled',
          Colors.red.shade600,
          Icons.cancel_outlined,
        );
      default:
        return _StatusStyle(status, Colors.grey, Icons.help_outline);
    }
  }

  // ------------------------------------------------------------- formatting
  static const _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
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

  /// '2026-08-12' + '10:30:00' -> 'Wed, 12 Aug · 10:30 AM'.
  /// Hand-rolled because the vendor app doesn't depend on intl; falls back to
  /// the raw values if the backend sends something unexpected.
  String _schedule(dynamic date, dynamic time) {
    final rawDate = '${date ?? ''}'.trim();
    final rawTime = '${time ?? ''}'.trim();
    final parsed = DateTime.tryParse('$rawDate $rawTime');
    if (parsed == null) {
      return [rawDate, rawTime].where((s) => s.isNotEmpty).join(' ');
    }

    final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final meridiem = parsed.hour < 12 ? 'AM' : 'PM';

    return '${_weekdays[parsed.weekday - 1]}, ${parsed.day} '
        '${_months[parsed.month - 1]} · $hour12:$minute $meridiem';
  }

  /// 'Today' / 'Tomorrow' for jobs coming up, otherwise null. Field staff scan
  /// for this before anything else on the card.
  String? _dayHint(dynamic date) {
    final parsed = DateTime.tryParse('${date ?? ''}'.trim());
    if (parsed == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(parsed.year, parsed.month, parsed.day);
    final days = target.difference(today).inDays;

    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days < 0) return 'Overdue';
    return null;
  }

  String _amount(dynamic amount) {
    final value = double.tryParse('${amount ?? ''}');
    if (value == null) return '₹${amount ?? 0}';

    final whole = value.truncate();
    final paise = ((value - whole) * 100).round();

    // Indian grouping: last 3 digits, then pairs (12,34,567).
    var text = whole.toString();
    if (text.length > 3) {
      final head = text.substring(0, text.length - 3);
      final tail = text.substring(text.length - 3);
      final grouped = head.replaceAllMapped(
        RegExp(r'(\d)(?=(\d\d)+$)'),
        (m) => '${m[1]},',
      );
      text = '$grouped,$tail';
    }

    // Only show paise when there are any — prices here are usually whole rupees.
    return paise == 0 ? '₹$text' : '₹$text.${paise.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('My Jobs'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'My Profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: 'Active (${_activeJobs.length})'),
            Tab(text: 'Completed (${_completedJobs.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildStateMessage(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load your jobs",
              message: _errorMessage!,
              action: ElevatedButton.icon(
                onPressed: _loadJobs,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildJobList(
                  _activeJobs,
                  Icons.work_outline,
                  'No active jobs',
                  'New jobs assigned to you will appear here.',
                ),
                _buildJobList(
                  _completedJobs,
                  Icons.task_alt,
                  'No completed jobs yet',
                  'Jobs you finish will be listed here.',
                ),
              ],
            ),
    );
  }

  Widget _buildJobList(
    List<dynamic> jobs,
    IconData emptyIcon,
    String emptyTitle,
    String emptyMessage,
  ) {
    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: jobs.isEmpty
          ? _buildStateMessage(
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
              scrollable: true,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: jobs.length,
              itemBuilder: (context, index) =>
                  _jobCard(Map<String, dynamic>.from(jobs[index])),
            ),
    );
  }

  Widget _jobCard(Map<String, dynamic> job) {
    final style = _statusStyle('${job['status']}');
    final address = '${job['address_text'] ?? ''}'.trim();
    final dayHint = _dayHint(job['preferred_date']);
    final isDone = job['status'] == 'COMPLETED';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => JobDetailScreen(job: job)),
            );
            _loadJobs();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${job['category_name'] ?? 'Job'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                'Job #${job['id']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              if (dayHint != null && !isDone) ...[
                                const SizedBox(width: 8),
                                _dayChip(dayHint),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statusPill(style),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1, color: _border),
                const SizedBox(height: 14),

                _detailRow(
                  Icons.person_outline,
                  '${job['customer_name'] ?? 'Customer'}',
                ),
                _detailRow(
                  Icons.event_outlined,
                  _schedule(job['preferred_date'], job['preferred_time']),
                ),
                if (address.isNotEmpty)
                  _detailRow(Icons.location_on_outlined, address, maxLines: 2),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Text(
                      _amount(job['amount']),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _paymentChip('${job['payment_status']}'),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Colors.grey.shade500,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(_StatusStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.color),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayChip(String hint) {
    final isOverdue = hint == 'Overdue';
    final color = isOverdue ? Colors.red.shade600 : Colors.deepOrange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        hint,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _paymentChip(String paymentStatus) {
    final isPaid = paymentStatus == 'PAID';
    final color = isPaid ? Colors.green.shade700 : Colors.orange.shade800;
    final label = isPaid
        ? 'Paid'
        : paymentStatus == 'UNPAID'
        ? 'Unpaid'
        : 'Payment pending';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String value, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Empty and error states. Kept scrollable inside the tabs so pull-to-refresh
  /// still works when a tab has nothing in it.
  Widget _buildStateMessage({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
    bool scrollable = false,
  }) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepOrange.withValues(alpha: 0.08),
              ),
              child: Icon(icon, size: 34, color: Colors.deepOrange),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );

    if (!scrollable) return content;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: content,
        ),
      ),
    );
  }
}
