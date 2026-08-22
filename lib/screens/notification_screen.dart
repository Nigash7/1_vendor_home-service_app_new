import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import 'support_screen.dart';
import 'ticket_detail_screen.dart';

/// The vendor app's accent, matching the jobs list, login and job detail
/// screens. Taken literally rather than from `colorScheme.primary`, because
/// the Material 3 scheme generated from the deepOrange seed comes out muted
/// and reads as a different colour beside the rest of the app.
const Color _accent = Colors.deepOrange;

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _service = NotificationService.instance;
  final _scrollController = ScrollController();

  final List<AppNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  String? _category; // null = All

  static const _filters = <String, String>{
    'All': '',
    'Jobs': 'BOOKING',
    'Earnings': 'PAYMENT',
    'Reviews': 'REVIEW',
    'Account': 'ACCOUNT',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        _hasMore &&
        !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.fetch(page: 1, category: _category);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetch(page: _page + 1, category: _category);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _page += 1;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // --------------------------------------------------------------- actions
  Future<void> _onTap(AppNotification note) async {
    if (!note.isRead) {
      final index = _items.indexWhere((n) => n.id == note.id);
      if (index != -1) {
        setState(() => _items[index] = note.copyWith(isRead: true));
      }
      _service.markRead(note.id).catchError((_) {});
    }
    _navigate(note);
  }

  /// Deep link handling. Extend this as you add routes.
  void _navigate(AppNotification note) {
    if (note.bookingId != null) {
      // Swap in your real screen:
      // Navigator.push(context, MaterialPageRoute(
      //   builder: (_) => JobDetailScreen(bookingId: note.bookingId!)));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open job #${note.bookingId}')));
      return;
    }
    if (note.route.startsWith('/support')) {
      // Route looks like /support/42 — the trailing segment is the ticket id.
      final ticketId = int.tryParse(note.route.split('/').last);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ticketId == null
              ? const SupportScreen()
              : TicketDetailScreen(ticketId: ticketId),
        ),
      );
      return;
    }
    if (note.route.startsWith('/earnings')) {
      // Navigator.push(context, MaterialPageRoute(builder: (_) => EarningsScreen()));
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead();
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          _items[i] = _items[i].copyWith(isRead: true);
        }
      });
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all notifications?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.clearAll();
      if (mounted) setState(_items.clear);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Removes the row immediately so the swipe feels instant, then puts it back
  /// if the server rejected the delete.
  Future<void> _delete(AppNotification note) async {
    final index = _items.indexWhere((n) => n.id == note.id);
    setState(() => _items.removeWhere((n) => n.id == note.id));
    try {
      await _service.delete(note.id);
    } catch (e) {
      if (!mounted) return;
      if (index != -1) setState(() => _items.insert(index, note));
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final unread = _items.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Row(
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unread > 0)
            IconButton(
              onPressed: _markAllRead,
              tooltip: 'Mark all read',
              icon: const Icon(Icons.done_all_rounded),
            ),
          if (_items.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'More',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (v) {
                if (v == 'clear') _clearAll();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, size: 20),
                      SizedBox(width: 10),
                      Text('Clear all'),
                    ],
                  ),
                ),
              ],
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: _buildFilters(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        children: _filters.entries.map((entry) {
          final value = entry.value.isEmpty ? null : entry.value;
          final selected = _category == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                if (selected) return;
                setState(() => _category = value);
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _accent : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: selected ? _accent : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _EmptyState(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load notifications",
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return const _EmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'Nothing here yet',
        message: "New jobs, schedule changes and payouts will show up here.",
      );
    }

    // Flatten into header/notification rows so the list can still paginate.
    final rows = <Object>[];
    String? lastGroup;
    for (final note in _items) {
      final group = _groupLabel(note.createdAt);
      if (group != lastGroup) {
        rows.add(group);
        lastGroup = group;
      }
      rows.add(note);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: rows.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= rows.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final row = rows[index];
          if (row is String) return _GroupHeader(label: row);

          final note = row as AppNotification;
          return _NotificationCard(
            note: note,
            onTap: () => _onTap(note),
            onDismissed: () => _delete(note),
          );
        },
      ),
    );
  }

  /// Buckets a notification under a date heading.
  static String _groupLabel(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(when.year, when.month, when.day);
    final days = today.difference(that).inDays;

    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'This week';
    return 'Earlier';
  }
}

// ===========================================================================
class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

// ===========================================================================
class _NotificationCard extends StatelessWidget {
  final AppNotification note;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _NotificationCard({
    required this.note,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Dismissible(
        key: ValueKey(note.id),
        // Swipe right to delete. The tile slides right, so the red background
        // is revealed on the left — alignment and padding follow it.
        direction: DismissDirection.startToEnd,
        dismissThresholds: const {DismissDirection.startToEnd: 0.4},
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: const Color(0xFFE24B4A),
            borderRadius: radius,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, color: Colors.white, size: 21),
              SizedBox(width: 10),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        onDismissed: (_) => onDismissed(),
        child: Material(
          color: Colors.white,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: note.isRead
                      ? Colors.grey.shade200
                      : note.accent.withValues(alpha: 0.35),
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Unread gets a coloured spine down the left edge.
                    if (!note.isRead)
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: note.accent,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(14),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          note.isRead ? 14 : 12,
                          14,
                          14,
                          14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 42,
                              width: 42,
                              decoration: BoxDecoration(
                                color: note.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                note.icon,
                                size: 21,
                                color: note.accent,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.title,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.3,
                                      fontWeight: note.isRead
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  if (note.body.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      note.body,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 13,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        note.timeAgo,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      if (!note.isRead) ...[
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _accent.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: const Text(
                                            'New',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: _accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 110,
              width: 110,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 52,
                color: _accent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 22),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
