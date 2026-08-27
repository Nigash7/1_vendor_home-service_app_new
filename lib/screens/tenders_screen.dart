import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/tender_format.dart';
import 'tender_detail_screen.dart';
import 'tender_project_screen.dart';

/// The vendor's whole tender world in one place:
///   Open      — requirements they can still bid on
///   My bids   — what they have quoted and what came of it
///   Projects  — the ones they won and are running
///
/// Three tabs rather than three entry points, because a vendor thinks in
/// terms of "where is my work coming from", not in terms of screens.
class TendersScreen extends StatefulWidget {
  final int initialTab;

  const TendersScreen({super.key, this.initialTab = 0});

  @override
  State<TendersScreen> createState() => _TendersScreenState();
}

class _TendersScreenState extends State<TendersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> _open = [];
  List<dynamic> _bids = [];
  List<dynamic> _projects = [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // One round trip each, in parallel — the three tabs are independent and
      // waiting for them in sequence would show three spinners in a row.
      final results = await Future.wait([
        ApiService.getOpenTenders(),
        ApiService.getMyBids(),
        ApiService.getMyTenderProjects(),
      ]);
      if (!mounted) return;
      setState(() {
        _open = results[0];
        _bids = results[1];
        _projects = results[2];
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

  Future<void> _openTender(int tenderId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TenderDetailScreen(tenderId: tenderId)),
    );
    if (changed == true) _load();
  }

  Future<void> _openProject(int tenderId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TenderProjectScreen(tenderId: tenderId),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tenderBg,
      appBar: AppBar(
        title: const Text('Tenders'),
        backgroundColor: tenderAccent,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
          tabs: [
            Tab(text: 'Open (${_open.length})'),
            Tab(text: 'My bids (${_bids.length})'),
            Tab(text: 'Projects (${_projects.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _stateMessage(
              icon: Icons.cloud_off_outlined,
              title: "Couldn't load tenders",
              message: _errorMessage!,
              action: ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tenderAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [_buildOpen(), _buildBids(), _buildProjects()],
            ),
    );
  }

  // ------------------------------------------------------------- open tab
  Widget _buildOpen() {
    if (_open.isEmpty) {
      return _refreshable(
        _stateMessage(
          icon: Icons.search_off_rounded,
          title: 'No open tenders',
          message: 'Nothing matching your categories right now. '
              'We will notify you the moment a customer posts one.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _open.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final tender = Map<String, dynamic>.from(_open[index]);
          return _OpenTenderCard(
            tender: tender,
            onTap: () => _openTender(tender['id']),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- bids tab
  Widget _buildBids() {
    if (_bids.isEmpty) {
      return _refreshable(
        _stateMessage(
          icon: Icons.gavel_rounded,
          title: 'No bids yet',
          message: 'Quotes you send land here so you can track what '
              'the customer decided.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _bids.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final bid = Map<String, dynamic>.from(_bids[index]);
          return _MyBidCard(bid: bid, onTap: () => _openTender(bid['tender']));
        },
      ),
    );
  }

  // --------------------------------------------------------- projects tab
  Widget _buildProjects() {
    if (_projects.isEmpty) {
      return _refreshable(
        _stateMessage(
          icon: Icons.construction_rounded,
          title: 'No projects yet',
          message: 'Tenders you win appear here, ready to start.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _projects.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final project = Map<String, dynamic>.from(_projects[index]);
          return _ProjectCard(
            project: project,
            onTap: () => _openProject(project['id']),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- helpers
  Widget _refreshable(Widget child) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        child,
      ],
    ),
  );

  Widget _stateMessage({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            if (action != null) ...[const SizedBox(height: 20), action],
          ],
        ),
      ),
    );
  }
}

/// A tender the vendor could bid on.
class _OpenTenderCard extends StatelessWidget {
  final Map<String, dynamic> tender;
  final VoidCallback onTap;

  const _OpenTenderCard({required this.tender, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final deadlineHint = tenderDeadlineHint(tender['bid_deadline']);
    final urgent = tenderDeadlineIsUrgent(tender['bid_deadline']);
    final bidCount = tender['bid_count'] ?? 0;

    return TenderCardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${tender['title'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (deadlineHint != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (urgent ? Colors.red : Colors.grey).withValues(
                      alpha: 0.12,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    deadlineHint,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: urgent
                          ? Colors.red.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            [
              tender['project_type_display'],
              tender['category_name'],
              tender['subcategory_name'],
            ].where((v) => v != null).join(' · '),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _fact(
                  Icons.account_balance_wallet_outlined,
                  'Their budget',
                  tenderMoney(tender['expected_budget']),
                ),
              ),
              Expanded(
                child: _fact(
                  Icons.gavel_rounded,
                  'Bids so far',
                  bidCount == 0 ? 'Be the first' : '$bidCount',
                ),
              ),
            ],
          ),
          if ('${tender['location_label'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${tender['location_label']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                if (tender['area_sqft'] != null)
                  Text(
                    '${tender['area_sqft']} sq ft',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, size: 17, color: Colors.grey.shade600),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ],
  );
}

/// One of the vendor's own quotes, and what became of it.
class _MyBidCard extends StatelessWidget {
  final Map<String, dynamic> bid;
  final VoidCallback onTap;

  const _MyBidCard({required this.bid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = bidStatusStyle('${bid['status']}');

    return TenderCardShell(
      onTap: onTap,
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
                      tenderMoney(bid['amount']),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Quoted ${tenderDate(bid['created_at'])}'
                      '${bid['timeline_days'] != null ? ' · ${bid['timeline_days']} days' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              TenderPill(style: style),
            ],
          ),
          if ('${bid['work_plan'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${bid['work_plan']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

/// A project the vendor won.
class _ProjectCard extends StatelessWidget {
  final Map<String, dynamic> project;
  final VoidCallback onTap;

  const _ProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = tenderStatusStyle('${project['status']}');

    return TenderCardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${project['title'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TenderPill(style: style),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${project['code'] ?? ''} · ${project['category_name'] ?? ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                tenderMoney(project['final_amount']),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              // The customer's payment position is the thing a vendor most
              // wants off this card without opening it.
              Text(
                _paymentLabel(project['payment_status']),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: project['payment_status'] == 'PAID'
                      ? Colors.green.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _paymentLabel(dynamic status) {
    switch (status) {
      case 'PAID':
        return 'Fully paid';
      case 'PARTIAL':
        return 'Part paid';
      default:
        return 'Nothing paid yet';
    }
  }
}
