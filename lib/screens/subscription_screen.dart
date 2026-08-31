import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/plan_card.dart';

/// The vendor's plan: what they are on, what else is available, and where a
/// request they have already sent has got to.
///
/// A vendor never grants themselves a tier — nothing charges them yet, so
/// tapping Upgrade sends an admin a request and changes nothing until it is
/// approved. The screen says so rather than implying an instant switch.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _errorMessage;
  int? _busyPlanId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await ApiService.getMySubscription();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? get _current =>
      _data?['current'] as Map<String, dynamic>?;

  Map<String, dynamic>? get _pending =>
      _data?['pending_request'] as Map<String, dynamic>?;

  List<dynamic> get _plans => (_data?['plans'] as List?) ?? const [];

  int? get _currentPlanId => (_current?['plan'] as Map?)?['id'] as int?;

  Future<void> _requestUpgrade(Map<String, dynamic> plan) async {
    final note = await _askForNote(plan);
    if (note == null) return;

    setState(() => _busyPlanId = plan['id'] as int?);
    try {
      await ApiService.requestPlanUpgrade(
        planId: plan['id'] as int,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Request sent. An admin will review your move to '
            '${plan['name']}.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  /// Returns the note to send, or null if the vendor backed out.
  Future<String?> _askForNote(Map<String, dynamic> plan) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move to ${plan['name']}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This sends a request to your admin. Your current plan does not '
              'change until they approve it, and nothing is charged here.',
              style: TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'Anything your admin should know',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw() async {
    final request = _pending;
    if (request == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text(
          'Your request for ${(request['plan'] as Map)['name']} will be '
          'taken back. You can ask again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.withdrawPlanUpgrade(request['id'] as int);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('My Plan'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildCurrentCard(),
                  if (_pending != null) ...[
                    const SizedBox(height: 12),
                    _buildPendingCard(),
                  ],
                  const SizedBox(height: 24),
                  _buildAvailableSection(),
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
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentCard() {
    final current = _current;

    if (current == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are not on a plan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'That does not stop you working — you can still take jobs and '
              'bid on tenders. Ask your admin to put you on one.',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    final plan = current['plan'] as Map<String, dynamic>;
    final daysLeft = current['days_remaining'] as int?;
    final expiringSoon = current['is_expiring_soon'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlanCard(plan: plan, isCurrent: true),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            current['is_lifetime'] == true
                ? 'Active — no expiry.'
                : 'Active until ${current['end_date']}'
                      '${daysLeft != null ? ' · $daysLeft day${daysLeft == 1 ? '' : 's'} left' : ''}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: expiringSoon ? FontWeight.bold : FontWeight.normal,
              color: expiringSoon ? Colors.orange.shade800 : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingCard() {
    final request = _pending!;
    final plan = request['plan'] as Map;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top, size: 20, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting on your admin',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'You asked to move to ${plan['name']}. You stay on your '
                  'current plan until it is approved.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _withdraw,
            style: TextButton.styleFrom(foregroundColor: Colors.orange.shade900),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableSection() {
    final others = _plans
        .whereType<Map<String, dynamic>>()
        .where((p) => p['id'] != _currentPlanId)
        .toList();

    if (others.isEmpty) {
      return const SizedBox.shrink();
    }

    final waiting = _pending != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Other plans',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          waiting
              ? 'Withdraw your open request before asking for a different plan.'
              : 'Asking sends a request to your admin. Nothing is charged in '
                    'the app.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        ...others.map(
          (plan) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlanCard(
              plan: plan,
              action: OutlinedButton(
                onPressed: waiting || _busyPlanId != null
                    ? null
                    : () => _requestUpgrade(plan),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepOrange,
                  side: const BorderSide(color: Colors.deepOrange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _busyPlanId == plan['id']
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Request this plan'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
